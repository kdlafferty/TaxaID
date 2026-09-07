#' Interactive Spatial Review of Consensus Taxa
#'
#' Opens a Shiny gadget for scrolling through consensus taxa -- grouped by
#' plausibility (e.g. \code{"expected"}/\code{"unexpected"}/\code{"unprecedented"}
#' from \code{add_posthoc_assessment()}'s \code{primary_plausibility}) -- and
#' seeing, for whichever taxon is selected, a live GBIF occurrence-density map
#' plus the same numeric spatial context [check_gbif_tile_range()] and
#' [compute_local_occurrence_distance()] compute, so a reviewer can look at a
#' flagged taxon's real-world distribution without leaving the pipeline.
#'
#' The map itself renders GBIF's live density tiles directly
#' (\code{leaflet::addTiles()} with the density-tile URL template) rather
#' than a static snapshot -- the reviewer can pan and zoom the actual tile
#' layer, at any resolution, the same way GBIF's own map viewer works. This
#' is a genuinely different (and free) consumer of the same GBIF tile API
#' [check_gbif_tile_range()] uses for its own alpha-channel analysis -- one
#' renders raw tiles client-side for a human to look at, the other decodes
#' pixels server-side for a number. Selecting a taxon triggers both: the
#' visual tile layer updates, and the sidebar's numeric context
#' (\code{check_gbif_tile_range()}/\code{compute_local_occurrence_distance()},
#' plus a pre-supplied \code{inat_range} lookup if given) recomputes.
#'
#' @section Cost:
#' Selecting a taxon triggers real, but free/cheap, network calls (GBIF name
#' resolution + \code{check_gbif_tile_range()}'s tile fetches, a few seconds).
#' The "Run AI Review" button is the one exception -- a real, BILLED LLM call
#' via \code{review_assignments()} -- and is deliberately never triggered
#' automatically; it only fires on an explicit click, and only appears at all
#' when \code{context} is supplied.
#'
#' @param input_df Data frame of consensus taxa (e.g. \code{consensus_final} after
#'   \code{add_posthoc_assessment()}). Must contain \code{taxon_col}; supply
#'   \code{plausibility_col = NULL} if there is no grouping column to filter
#'   by.
#' @param query_lat,query_lon Numeric scalars. The study site to check
#'   distances/tiles against.
#' @param taxon_col Character. Column in \code{input_df} naming each taxon.
#'   Default \code{"primary_taxon"}.
#' @param plausibility_col Character or \code{NULL}. Column in \code{input_df} used
#'   to group the taxon dropdown (e.g. \code{"primary_plausibility"}).
#'   \code{NULL} shows every taxon in one unfiltered list. Default
#'   \code{"primary_plausibility"}.
#' @param occurrence_data Data frame or \code{NULL}. Already-fetched
#'   occurrence records this study kept (e.g. \code{occurrences_clean})
#'   passed straight to [compute_local_occurrence_distance()] and overlaid
#'   on the map as small, semi-transparent points for the selected taxon
#'   (deliberately understated so they don't visually overwhelm the GBIF
#'   tile layer underneath). \code{NULL} (default) omits the free/local
#'   panel and the point overlay entirely.
#' @param excluded_occurrence_data Data frame or \code{NULL}. Occurrence
#'   records this study's own GBIF quality/outlier/institution/spatial-QC
#'   filtering excluded, in the same shape as \code{occurrence_data} --
#'   overlaid as hollow red rings, distinct from \code{occurrence_data}'s
#'   solid points, for provenance ("what did we have and choose not to use")
#'   rather than as evidence of presence. Not computed here -- reconstruct
#'   it yourself, e.g. \code{dplyr::anti_join(raw_gbif, geo_outlier_check, by
#'   = "gbifID")} for the \code{filter_gbif_quality()} stage specifically (see
#'   `TaxaFetch::filter_gbif_quality()`'s own \code{removed_records}
#'   attribute for exact per-record reasons when that attribute is still
#'   attached). \code{NULL} (default) omits this overlay.
#' @param occurrence_taxon_col,occurrence_lat_col,occurrence_lon_col
#'   Character. Column names shared by \code{occurrence_data} AND
#'   \code{excluded_occurrence_data}. Defaults match
#'   [compute_local_occurrence_distance()]'s own defaults.
#' @param inat_range Data frame or \code{NULL}. Pre-computed
#'   \code{TaxaFetch::check_inat_range()} output (one row per taxon, with
#'   \code{in_range}/\code{n_observations}/\code{matched_name}) to look up by
#'   taxon name -- checked FIRST, for free, before any live call (see
#'   \code{live_inat_check} below). Real, confirmed limitation this param
#'   alone can't cover: \code{check_inat_range()} is typically only ever run
#'   on a pipeline's own undetected/unreferenced candidate list (e.g. Step 8c
#'   of a workflow script), not every taxon in a consensus table -- verified
#'   directly against a real dataset that taxa flagged \code{"expected"} or
#'   \code{"unexpected"} (not \code{"unprecedented"}) are routinely absent
#'   from it entirely, which is why \code{live_inat_check} exists.
#' @param inat_taxon_col Character. Taxon-name column in \code{inat_range}.
#'   Default \code{"taxon_name"}.
#' @param live_inat_check Logical. When a taxon has no row in
#'   \code{inat_range} (including when \code{inat_range} itself is
#'   \code{NULL}), fall back to a real, live
#'   \code{TaxaFetch::check_inat_range()} call for just that one taxon.
#'   Default \code{TRUE} -- unlike \code{review_assignments()}'s "Run AI
#'   Review" button, this is free (no LLM billing) and fires automatically
#'   on selection, matching \code{check_gbif_tile_range()}'s own always-on
#'   treatment. Requires the \code{TaxaFetch} package and a real
#'   \code{INAT_API_TOKEN}; silently falls back to "no data" (not an error)
#'   when either is unavailable, or when iNat itself has no polygon for the
#'   resolved taxon (surfaced via \code{range_status} in that case, e.g.
#'   \code{"taxon_not_found"}/\code{"no_polygon"}, rather than a blanket "no
#'   data" that can't be told apart from "never checked").
#' @param inat_cache_dir Character or \code{NULL}. Forwarded to
#'   \code{check_inat_range()}'s own \code{cache_dir} when
#'   \code{live_inat_check} fires -- caches per-taxon iNat range polygons on
#'   disk so re-selecting the same taxon (in this session or a later one)
#'   doesn't re-download it. \code{NULL} (default) disables caching, matching
#'   \code{check_inat_range()}'s own default.
#' @param inat_radius_km Numeric. Search radius (kilometers) for the real
#'   iNaturalist observation points plotted on the map (see
#'   \code{.fetch_inat_points()}, internal) -- distinct from
#'   \code{live_inat_check}'s range-polygon check, which has no radius
#'   concept. Default \code{500} -- confirmed live this needs to be wide,
#'   not just permissive: the individual-point map layer replaced an
#'   earlier raster tile layer that always covered the full visible map
#'   (continuous world density, like GBIF's own tiles), so a real
#'   click-through correctly flagged a smaller default (50km, copied
#'   unexamined from an unrelated function's own default) as confining
#'   points to "a small region" compared to what the gadget used to show.
#'   A dashed circle of this exact radius is drawn on the map (grouped with
#'   the iNat points layer, so toggling one toggles both) specifically so a
#'   taxon with no visible points nearby doesn't read as "no iNat data
#'   exists" when it may just mean "none within this radius."
#' @param context,target_group,marker,llm_fn Passed straight to
#'   [review_assignments()] when "Run AI Review" is clicked. \code{context}
#'   defaulting to \code{NULL} (rather than being required, unlike
#'   \code{review_assignments()} itself) is what hides the button entirely --
#'   supply it to enable on-demand AI review.
#' @param tile Character. Leaflet base-map tile provider (the reference map
#'   underneath the GBIF density overlay). Default \code{"CartoDB.Positron"}
#'   -- a muted, mostly-grayscale basemap chosen specifically so GBIF's own
#'   density colours stand out (a busier basemap like \code{"OpenStreetMap"}'s
#'   default styling visually competes with them, especially at low zoom
#'   where GBIF's own density pixels are small). Try
#'   \code{"CartoDB.PositronNoLabels"} for an even plainer background (drops
#'   place-name labels too).
#' @param gbif_style Character. GBIF map API \code{style} query parameter,
#'   controlling how GBIF itself renders density (colour ramp, point vs.
#'   area aggregation). Default \code{"classic.point"} -- GBIF's own default
#'   rendering, matching what GBIF's own map viewer shows. A bare
#'   \code{".point"} style is automatically upgraded to its \code{".poly"}
#'   counterpart and combined with \code{gbif_bin_size} (below) unless it's
#'   a Heat-family style, which has no \code{.poly} counterpart. Other
#'   \code{.point} styles (e.g. \code{"purpleHeat.point"}) are valid and can
#'   look bolder against a light basemap; pass one to compare.
#' @param gbif_bin_size Integer or \code{NULL}. GBIF map API's \code{bin=
#'   square}/\code{squareSize} binning parameters, aggregating raw
#'   single-pixel occurrence dots into visibly larger squares -- confirmed
#'   live before choosing this default: \code{squareSize} params are
#'   silently NO-OPS when \code{style} stays \code{.point}-suffixed
#'   (identical bytes with/without them), and only take effect once the
#'   style is switched to its \code{.poly} counterpart, which is why
#'   \code{gbif_style} is auto-upgraded above. Default \code{256L}, chosen
#'   from real measurements against the SPARSE species this gadget is
#'   actually meant to review (this thread's own real "unprecedented"
#'   candidates, at the real zoom-7 study-site tile), not a common/
#'   everywhere-present species -- an earlier, smaller default (64) was
#'   revised after a real click-through reported no noticeable change,
#'   which real measurement confirmed: for a real, genuinely sparse GBIF
#'   record set at that exact tile, raw \code{.point} pixels covered under
#'   0.1%; \code{squareSize=64} only reached ~1-2.5%, visually
#'   indistinguishable from unbinned dots on a full map pane. \code{256}
#'   reaches ~10-15% coverage for the same real sparse species (a ~60-140x
#'   increase over raw pixels) while a maximally common, everywhere-present
#'   species (checked separately, not this gadget's typical use case) only
#'   reaches ~26% -- visibly bigger without turning into a solid blob.
#'   \code{NULL} disables binning entirely, reverting to \code{gbif_style}
#'   exactly as supplied (the pre-2026-08-07 default behaviour).
#'   \code{".poly"}-suffixed styles combined with \code{gbif_bin_size =
#'   NULL} (unbinned) can render as a completely EMPTY tile at a real
#'   zoom/species combination that raw \code{.point} styles render
#'   correctly -- confirmed live, not a safe combination -- so this is only
#'   ever applied together with binning, never on its own. \strong{A binned
#'   square can visually sit offset from a point's true location by up to
#'   \code{gbif_bin_size} pixels}, since GBIF snaps each occurrence to its
#'   containing bin before drawing it -- a real, expected consequence of
#'   aggregation, not a data or rendering bug (a single domestic-cat record
#'   appearing a few km into open water at the default \code{256L} binning
#'   is exactly this: GBIF's real, unfiltered occurrence data plus one
#'   coarse pixel's worth of legitimate positional imprecision from
#'   binning, not a broken map layer). See also
#'   [check_gbif_tile_range()]'s own \verb{What the PNG can and can't tell
#'   you} section -- density tiles are a display aid, not an exact-count
#'   source, in this gadget as much as there.
#' @param gbif_year_range Character or \code{NULL}. GBIF map API \code{year}
#'   query parameter (e.g. \code{"1995,2025"}), display-only -- affects
#'   only the visual tile layer, NOT [check_gbif_tile_range()]'s own
#'   distance/patch numbers (which deliberately stay all-time/global, the
#'   right question for "is this plausible anywhere, ever" rather than
#'   "within our exact study window"). Worth knowing: the density map is
#'   all-time and worldwide by default, which is often a much LARGER pool
#'   of records than a study's own date- and quality-filtered GBIF fetch --
#'   confirmed directly against the real GBIF tile API that a narrower
#'   \code{year} range genuinely reduces what's rendered (a real, working
#'   filter, not a cosmetic one). \code{NULL} (default) shows GBIF's full
#'   all-time record, matching GBIF's own default map view.
#'
#' @return \code{NULL} invisibly. The gadget is for interactive exploration
#'   only.
#'
#' @seealso [check_gbif_tile_range()], [compute_local_occurrence_distance()],
#'   [review_assignments()], \code{TaxaHabitat::review_spatial_flags()} for
#'   the equivalent gadget pattern this one follows.
#'
#' @examples
#' \dontrun{
#' review_spatial_context(
#'   input_df               = consensus_final,
#'   query_lat        = STUDY_LAT, query_lon = STUDY_LON,
#'   occurrence_data  = occurrences_clean,
#'   inat_range       = inat_range,
#'   context          = list(geography = "Lake Michigan, Burns/Indiana Harbor",
#'                           habitat   = "harbor, standing water"),
#'   target_group     = "fish",
#'   marker           = "12S eDNA"
#' )
#' }
#'
#' @importFrom TaxaTools %||%
#' @export
review_spatial_context <- function(input_df,
                                    query_lat,
                                    query_lon,
                                    taxon_col             = "primary_taxon",
                                    plausibility_col      = "primary_plausibility",
                                    occurrence_data       = NULL,
                                    excluded_occurrence_data = NULL,
                                    occurrence_taxon_col  = "taxon_name",
                                    occurrence_lat_col    = "decimalLatitude",
                                    occurrence_lon_col    = "decimalLongitude",
                                    inat_range            = NULL,
                                    inat_taxon_col        = "taxon_name",
                                    live_inat_check       = TRUE,
                                    inat_cache_dir        = NULL,
                                    inat_radius_km        = 500,
                                    context               = NULL,
                                    target_group          = NULL,
                                    marker                = NULL,
                                    llm_fn                = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                                    tile                  = "CartoDB.Positron",
                                    gbif_style            = "classic.point",
                                    gbif_bin_size         = 256L,
                                    gbif_year_range       = NULL) {

  for (pkg in c("shiny", "miniUI", "leaflet", "httr2", "png")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "review_spatial_context: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ))
    }
  }
  if (!interactive()) {
    stop("review_spatial_context: must be run in an interactive R session.")
  }

  if (!is.data.frame(input_df)) stop("review_spatial_context: 'input_df' must be a data frame.")
  if (!taxon_col %in% names(input_df))
    stop(sprintf("review_spatial_context: column '%s' not found in input_df.", taxon_col))
  if (!is.null(plausibility_col) && !plausibility_col %in% names(input_df))
    stop(sprintf("review_spatial_context: column '%s' not found in input_df.", plausibility_col))
  if (!is.numeric(query_lat) || length(query_lat) != 1L || is.na(query_lat))
    stop("review_spatial_context: query_lat must be a single non-NA numeric value.")
  if (!is.numeric(query_lon) || length(query_lon) != 1L || is.na(query_lon))
    stop("review_spatial_context: query_lon must be a single non-NA numeric value.")

  .review_spatial_context_impl(
    input_df = input_df, query_lat = query_lat, query_lon = query_lon, taxon_col = taxon_col,
    plausibility_col = plausibility_col, occurrence_data = occurrence_data,
    excluded_occurrence_data = excluded_occurrence_data,
    occurrence_taxon_col = occurrence_taxon_col, occurrence_lat_col = occurrence_lat_col,
    occurrence_lon_col = occurrence_lon_col, inat_range = inat_range,
    inat_taxon_col = inat_taxon_col, live_inat_check = live_inat_check,
    inat_cache_dir = inat_cache_dir, inat_radius_km = inat_radius_km, context = context,
    target_group = target_group, marker = marker, llm_fn = llm_fn, tile = tile,
    gbif_style = gbif_style, gbif_bin_size = gbif_bin_size, gbif_year_range = gbif_year_range
  )
}


#' Gadget UI/server construction, split from review_spatial_context() so it
#' can be invoked directly (bypassing the interactive()-only gate) for live
#' Chrome-based verification during development -- not exported, not a
#' supported public bypass of the gate. Arguments are identical to
#' review_spatial_context()'s own, already validated by the caller.
#' @noRd
.review_spatial_context_impl <- function(input_df, query_lat, query_lon, taxon_col,
                                         plausibility_col, occurrence_data,
                                         excluded_occurrence_data,
                                         occurrence_taxon_col, occurrence_lat_col,
                                         occurrence_lon_col, inat_range, inat_taxon_col,
                                         live_inat_check, inat_cache_dir, inat_radius_km,
                                         context, target_group, marker, llm_fn, tile,
                                         gbif_style, gbif_bin_size, gbif_year_range) {

  all_taxa <- sort(unique(input_df[[taxon_col]][!is.na(input_df[[taxon_col]])]))
  if (length(all_taxa) == 0L)
    stop("review_spatial_context: no non-NA taxa found in input_df[[taxon_col]].")

  plaus_choices <- if (is.null(plausibility_col)) {
    NULL
  } else {
    c("All", sort(unique(as.character(input_df[[plausibility_col]][!is.na(input_df[[plausibility_col]])]))))
  }

  # ---------------------------------------------------------------------------
  # UI
  # ---------------------------------------------------------------------------
  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      "Spatial Review: GBIF / iNat Context",
      right = miniUI::miniTitleBarButton("done", "Close", primary = TRUE)
    ),
    miniUI::miniContentPanel(
      padding = 0,
      shiny::div(
        style = "display:flex;width:100%;height:100%;",

        shiny::div(
          style = "flex:1;min-width:0;position:relative;",
          leaflet::leafletOutput("map", width = "100%", height = "100%")
        ),

        shiny::div(
          style = paste0(
            "width:340px;flex-shrink:0;padding:12px;border-left:1px solid #ddd;",
            "background:#fafafa;overflow-y:auto;"
          ),

          if (!is.null(plaus_choices)) shiny::tagList(
            shiny::h4("Plausibility", style = "margin:6px 0 4px;font-size:13px;"),
            shiny::selectInput("plaus", label = NULL, choices = plaus_choices,
                               selected = "All", width = "100%")
          ) else NULL,

          shiny::h4("Taxon", style = "margin:6px 0 4px;font-size:13px;"),
          shiny::selectInput("taxon", label = NULL, choices = all_taxa, width = "100%"),

          shiny::hr(style = "margin:8px 0;"),
          shiny::uiOutput("stats_panel"),

          if (!is.null(context)) shiny::tagList(
            shiny::hr(style = "margin:8px 0;"),
            shiny::actionButton("run_ai", "Run AI Review", width = "100%"),
            shiny::div(style = "font-size:10px;color:#999;margin-top:2px;",
                      "Makes a real, billed LLM call."),
            shiny::uiOutput("ai_panel")
          ) else NULL
        )
      )
    )
  )

  server <- .build_spatial_context_server(
    input_df = input_df, query_lat = query_lat, query_lon = query_lon, taxon_col = taxon_col,
    plausibility_col = plausibility_col, all_taxa = all_taxa, plaus_choices = plaus_choices,
    occurrence_data = occurrence_data, excluded_occurrence_data = excluded_occurrence_data,
    occurrence_taxon_col = occurrence_taxon_col,
    occurrence_lat_col = occurrence_lat_col, occurrence_lon_col = occurrence_lon_col,
    inat_range = inat_range, inat_taxon_col = inat_taxon_col,
    live_inat_check = live_inat_check, inat_cache_dir = inat_cache_dir,
    inat_radius_km = inat_radius_km, context = context, target_group = target_group,
    marker = marker, llm_fn = llm_fn, tile = tile, gbif_style = gbif_style,
    gbif_bin_size = gbif_bin_size, gbif_year_range = gbif_year_range
  )

  shiny::runGadget(ui, server, viewer = shiny::paneViewer(minHeight = 500))
}


#' Build the gadget's server function, split out from
#' .review_spatial_context_impl() so it can be driven directly with
#' shiny::testServer() -- a full browser isn't a practical way to test a
#' page with a persistent Shiny websocket connection (confirmed: standard
#' browser-automation "wait for network idle" heuristics hang indefinitely
#' against a live Shiny session), so the reactive logic is verified this way
#' instead. Returns a function(input, output, session), the shape
#' shiny::runGadget()/shiny::testServer() both expect. All arguments are
#' already-validated config from review_spatial_context(); all_taxa/
#' plaus_choices are precomputed once by the caller rather than recomputed
#' per session.
#' @noRd
.build_spatial_context_server <- function(input_df, query_lat, query_lon, taxon_col,
                                          plausibility_col, all_taxa, plaus_choices,
                                          occurrence_data, excluded_occurrence_data,
                                          occurrence_taxon_col,
                                          occurrence_lat_col, occurrence_lon_col,
                                          inat_range, inat_taxon_col,
                                          live_inat_check, inat_cache_dir, inat_radius_km,
                                          context, target_group, marker, llm_fn, tile,
                                          gbif_style, gbif_bin_size, gbif_year_range) {
  function(input, output, session) {

    shiny::observeEvent(input$plaus, {
      shiny::req(!is.null(plaus_choices))
      taxa <- if (input$plaus == "All") {
        all_taxa
      } else {
        sort(unique(input_df[[taxon_col]][input_df[[plausibility_col]] %in% input$plaus & !is.na(input_df[[taxon_col]])]))
      }
      shiny::updateSelectInput(session, "taxon", choices = taxa)
    }, ignoreNULL = TRUE)

    taxon_key <- shiny::reactive({
      shiny::req(input$taxon)
      .resolve_gbif_taxon_key(input$taxon)
    })

    gbif_res <- shiny::reactive({
      key <- taxon_key()
      # NOT shiny::req(!is.na(key)) here: req()'s silent-stop propagates to
      # ANY caller reading this reactive (including output$stats_panel,
      # which reads gbif_res() unconditionally) -- an unresolvable taxon
      # name would silently blank the WHOLE stats panel, including the
      # Local/iNat sections that don't even depend on this. Returning NULL
      # instead lets stats_panel's own "could not resolve" branch (which
      # checks taxon_key() directly) handle this case without losing the
      # rest of the panel.
      if (is.na(key)) return(NULL)
      tryCatch(
        check_gbif_tile_range(taxon_key = key, query_lat = query_lat, query_lon = query_lon),
        error = function(e) NULL
      )
    })

    local_res <- shiny::reactive({
      shiny::req(input$taxon)
      if (is.null(occurrence_data)) return(NULL)
      tryCatch(
        compute_local_occurrence_distance(
          taxon_names = input$taxon, query_lat = query_lat, query_lon = query_lon,
          occurrence_data = occurrence_data, taxon_col = occurrence_taxon_col,
          lat_col = occurrence_lat_col, lon_col = occurrence_lon_col
        ),
        error = function(e) NULL
      )
    })

    # Static lookup first (free), live check_inat_range() call as fallback --
    # confirmed necessary against real data, not a hypothetical: a pipeline's
    # own inat_range is typically scoped to its "unprecedented" candidate
    # list only, so "expected"/"unexpected" taxa (the majority of a real
    # consensus table) are routinely absent from it, not covered at all by
    # the static lookup alone.
    inat_row <- shiny::reactive({
      shiny::req(input$taxon)

      if (!is.null(inat_range) && inat_taxon_col %in% names(inat_range)) {
        hit <- inat_range[inat_range[[inat_taxon_col]] %in% input$taxon, , drop = FALSE]
        if (nrow(hit) > 0L) return(hit[1L, , drop = FALSE])
      }

      if (isTRUE(live_inat_check) && requireNamespace("TaxaFetch", quietly = TRUE)) {
        live <- tryCatch(
          TaxaFetch::check_inat_range(
            taxon_names = input$taxon, lat = query_lat, lng = query_lon,
            cache_dir = inat_cache_dir, verbose = FALSE
          ),
          error = function(e) NULL
        )
        # check_inat_range() always returns exactly one row per input taxon,
        # even when nothing is found (NA-filled, with a real range_status
        # like "taxon_not_found"/"no_polygon") -- returned as-is rather than
        # treated as absent, so the sidebar can show that real status instead
        # of a generic "no data" indistinguishable from "never checked."
        if (!is.null(live) && nrow(live) > 0L) return(live[1L, , drop = FALSE])
      }

      NULL
    })

    output$stats_panel <- shiny::renderUI({
      shiny::req(input$taxon)
      l  <- local_res()
      g  <- gbif_res()
      ir <- inat_row()

      blocks <- list()

      if (!is.null(l)) {
        txt <- if (l$n_local_records == 0L) {
          "Local (free): 0 records in this study's own occurrence data"
        } else {
          sprintf("Local (free): %d record(s), nearest %.1f km away",
                  l$n_local_records, l$dist_nearest_km)
        }
        blocks <- c(blocks, list(shiny::p(txt, style = "font-size:12px;margin:4px 0;")))
      }

      if (!is.null(taxon_key()) && is.na(taxon_key())) {
        blocks <- c(blocks, list(shiny::p(
          "GBIF: could not resolve a usageKey for this name.",
          style = "font-size:12px;margin:4px 0;color:#999;"
        )))
      } else if (is.null(g)) {
        blocks <- c(blocks, list(shiny::p("GBIF: checking...", style = "font-size:12px;margin:4px 0;color:#999;")))
      } else if (isTRUE(g$beyond_buffer)) {
        blocks <- c(blocks, list(shiny::p(
          "GBIF: no occurrence found anywhere globally",
          style = "font-size:12px;margin:4px 0;font-weight:600;color:#b91c1c;"
        )))
      } else {
        esc <- if (isTRUE(g$escalated)) sprintf(" (escalated to zoom %d)", g$zoom_used) else ""
        blocks <- c(blocks, list(shiny::p(
          sprintf("GBIF: nearest occurrence ~%.0f km away, patch ~%.1f km across%s",
                  g$dist_nearest_occupied_km, g$patch_diameter_km, esc),
          style = "font-size:12px;margin:4px 0;"
        )))
      }

      # Always show an iNat line whenever the feature is active at all
      # (either static inat_range was supplied, or live_inat_check can fire)
      # -- silence otherwise reads as "iNat isn't working," when it's often
      # just a real coverage gap. Confirmed directly against real data: a
      # pipeline's own inat_range is typically scoped to its
      # "unprecedented" candidate list only, so "expected"/"unexpected"
      # taxa (most of a real consensus table) are routinely absent from the
      # static lookup entirely -- inat_row()'s live fallback covers that gap
      # when enabled; this block just reports whatever it found (or didn't).
      if (!is.null(inat_range) || isTRUE(live_inat_check)) {
        if (is.null(ir)) {
          blocks <- c(blocks, list(shiny::p(
            "iNat: no data (absent from inat_range, and no live check available/enabled)",
            style = "font-size:12px;margin:4px 0;color:#999;"
          )))
        } else {
          mismatch <- !is.na(ir$matched_name) &&
            tolower(trimws(ir$matched_name)) != tolower(trimws(input$taxon))
          parts <- character(0)
          if (mismatch) parts <- c(parts, sprintf("matched to '%s' (differs from query!)", ir$matched_name))
          if (!is.null(ir$in_range) && !is.na(ir$in_range))
            parts <- c(parts, if (isTRUE(ir$in_range)) "in range" else "outside range")
          if (!is.null(ir$n_observations) && !is.na(ir$n_observations))
            parts <- c(parts, sprintf("%s obs", format(ir$n_observations, big.mark = ",")))
          txt <- if (length(parts) == 0L) {
            # Checked (static or live) but nothing usable came back --
            # surface the real range_status (e.g. "taxon_not_found"/
            # "no_polygon" from a live check) when available, rather than a
            # blanket "empty" that can't be told apart from "never checked."
            status <- if (!is.null(ir$range_status) && !is.na(ir$range_status)) ir$range_status else "empty"
            sprintf("iNat: checked, no usable data (%s)", status)
          } else {
            paste0("iNat: ", paste(parts, collapse = ", "))
          }
          blocks <- c(blocks, list(shiny::p(
            txt,
            style = sprintf("font-size:12px;margin:4px 0;%s",
                            if (mismatch) "font-weight:600;color:#b45309;" else "")
          )))
          # The map's iNat observation-tile layer needs taxon_id specifically
          # (not just in_range/n_observations) -- flag explicitly when it's
          # missing so a blank iNat layer on the map doesn't read as broken.
          has_taxon_id <- !is.null(ir$taxon_id) && !is.na(ir$taxon_id)
          if (!has_taxon_id) {
            blocks <- c(blocks, list(shiny::p(
              "iNat map layer: not shown (no taxon_id in this row)",
              style = "font-size:11px;margin:2px 0 4px;color:#999;"
            )))
          }
        }
      }

      shiny::tagList(blocks)
    })

    # Static legend, built once (doesn't depend on the selected taxon) --
    # explains the 4 toggleable overlays below plus the fixed study-site
    # marker, since none of GBIF/iNat/local-occurrence styling is
    # self-explanatory without a key once several overlays can be on at once.
    # GBIF gradient stops are keyed on the ACTUAL gbif_style in use, not a
    # single hardcoded assumption -- a prior version hardcoded the "classic"
    # ramp's colors regardless of gbif_style, which was simply wrong the
    # first time a user passed gbif_style="purpleHeat.point" (real color,
    # confirmed by sampling live tiles: black -> purple -> magenta -> pink,
    # nothing resembling yellow at any point). See .gbif_legend_swatch()
    # (below, extracted out for direct unit testing) for the real, sampled
    # pixel RGB values this is built from.
    .gbif_swatch <- .gbif_legend_swatch(gbif_style)
    .gbif_legend_gradient <- .gbif_swatch$gradient
    .gbif_legend_label <- .gbif_swatch$label

    .marker_icon_uri <- tryCatch({
      # Embeds leaflet's OWN bundled default marker icon (the exact PNG
      # leaflet::addMarkers() draws with no custom icon= -- confirmed by
      # inspecting the installed leaflet package's htmlwidgets assets) as a
      # data URI, so the legend swatch is pixel-identical to the real map
      # marker rather than an emoji/CSS approximation of it -- generated at
      # runtime so it can never drift from whatever leaflet version is
      # actually installed.
      icon_path <- system.file(
        "htmlwidgets/lib/leaflet/images/marker-icon.png", package = "leaflet"
      )
      if (!nzchar(icon_path)) stop("marker-icon.png not found")
      raw <- readBin(icon_path, "raw", file.info(icon_path)$size)
      sprintf("data:image/png;base64,%s", jsonlite::base64_enc(raw))
    }, error = function(e) NULL)

    .legend_html <- paste0(
      "<div style='background:white;padding:6px 9px;border-radius:4px;",
      "box-shadow:0 1px 4px rgba(0,0,0,0.35);font-size:11px;line-height:1.7;'>",
      "<div><span style='display:inline-block;width:14px;height:8px;",
      sprintf("background:%s;", .gbif_legend_gradient),
      sprintf("margin-right:6px;vertical-align:middle;'></span>%s</div>", .gbif_legend_label),
      "<div><span style='display:inline-block;width:8px;height:8px;",
      "border-radius:50%;background:#1d4ed8;margin-right:7px;",
      "vertical-align:middle;'></span>Local occurrence (kept)</div>",
      "<div><span style='display:inline-block;width:8px;height:8px;",
      "border-radius:50%;border:1.5px solid #dc2626;margin-right:6px;",
      "vertical-align:middle;'></span>Local occurrence (excluded)</div>",
      "<div><span style='display:inline-block;width:8px;height:8px;",
      "border-radius:50%;background:#16a34a;margin-right:7px;",
      sprintf(
        "vertical-align:middle;'></span>iNaturalist observation (dashed circle = %s km search radius)</div>",
        format(inat_radius_km, big.mark = ",")
      ),
      "<div>",
      if (!is.null(.marker_icon_uri)) {
        sprintf(
          "<img src='%s' style='height:14px;vertical-align:middle;margin-right:5px;'/>",
          .marker_icon_uri
        )
      } else {
        "&#128205; "
      },
      "Study site</div>",
      "</div>"
    )

    output$map <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::addProviderTiles(tile) |>
        # zoom = 7, not 5: verified directly against real check_gbif_tile_range()
        # output that GBIF's own density blobs occupy MORE on-screen pixels at
        # higher zoom (patch_size_px 21 -> 52 -> 95 across zoom 5 -> 6 -> 7 for
        # a real test case) before fragmenting into isolated single pixels
        # beyond zoom 7 -- 7 is the real, measured sweet spot, not a guess.
        leaflet::setView(lng = query_lon, lat = query_lat, zoom = 7) |>
        leaflet::addControl(html = .legend_html, position = "bottomright")
    })

    shiny::observeEvent(input$taxon, {
      shiny::req(input$taxon)
      proxy <- leaflet::leafletProxy("map")
      proxy <- leaflet::clearGroup(proxy, "gbif_tiles")
      proxy <- leaflet::clearGroup(proxy, "inat_points")
      proxy <- leaflet::clearGroup(proxy, "occ_points")
      proxy <- leaflet::clearGroup(proxy, "excluded_points")
      proxy <- leaflet::clearGroup(proxy, "site")

      key <- taxon_key()
      if (!is.na(key)) {
        # URL construction (the .point->.poly auto-upgrade + bin=square/
        # squareSize params + Heat-family exclusion) lives in
        # .gbif_tile_url(), extracted out for direct unit testing rather
        # than only exercised implicitly through the full gadget -- see
        # that function's own comment for the "confirmed live, silent
        # no-op on .point styles" verification record.
        url <- .gbif_tile_url(key, gbif_style, gbif_bin_size, gbif_year_range)
        # tileSize=512 + zoomOffset=-1 together (NOT tileSize alone -- see
        # below for why that earlier attempt broke). This is the standard
        # Leaflet "retina tile" recipe: GBIF's own z/x/y addressing follows
        # the normal 256px-grid convention (confirmed repeatedly across this
        # whole thread via real occupied-pixel checks at hand-computed z/x/y
        # coordinates), but its @1x.png response is a real 512x512 image --
        # i.e. GBIF's default tile is already double-resolution ("@2x") for
        # its own addressed area, exactly the shape this Leaflet option pair
        # exists for. zoomOffset=-1 requests one zoom level COARSER (whose
        # standard-grid tile covers exactly the area a tileSize=512 slot
        # spans at the map's displayed zoom), so the real, correctly
        # addressed 512px image fills a 512 CSS-px slot with no forced
        # downscaling -- a genuine, correctly-addressed ~2x size increase in
        # both dimensions, not a display trick. Verified live before
        # shipping this time, not reasoned from memory alone (the source of
        # the earlier regression): built a standalone (non-Shiny) leaflet
        # page with both this option pair and the prior no-override default
        # side by side, screenshotted both in a real Chrome tab at zoom 7 AND
        # after zooming in twice more, and confirmed the tileSize=512/
        # zoomOffset=-1 version renders visibly larger, correctly positioned
        # squares (same real GreatLakes species/coordinates, matching
        # clusters in Chicago/Detroit/etc.) with no tile gaps, no
        # misalignment against the basemap, and no console errors at either
        # zoom. A PRIOR version set tileSize=512 ALONE (no zoomOffset),
        # which requests the WRONG z/x/y for the slot size -- that IS a
        # genuine bug (confirmed via Leaflet's own source:
        # _pxBoundsToTileRange() divides the map's shared world-pixel bounds
        # by EACH LAYER's OWN tileSize to compute its tile indices, so an
        # unpaired tileSize change alone desyncs addressing) -- the real
        # regression a previous round hit and fully reverted. This is not a
        # repeat of that mistake: zoomOffset=-1 is the exact compensation
        # tileSize=512 needs to stay correctly addressed.
        #
        # No tileOptions(opacity=) here, deliberately: an earlier round DID
        # add an opacity override to dim the tile layer, and a real
        # click-through reported that made sparse species (this gadget's
        # actual use case) HARDER to see against the basemap, not easier --
        # reverted, and left off since. GBIF's own colour ramp already
        # encodes density; a second opacity multiplier on top of it fights
        # that signal rather than clarifying it.
        proxy <- leaflet::addTiles(
          proxy, urlTemplate = url, group = "gbif_tiles",
          options = leaflet::tileOptions(tileSize = 512, zoomOffset = -1)
        )
      }

      # iNat observations, plotted as real individual point markers rather
      # than iNaturalist's own raster observation-tile endpoint
      # (api.inaturalist.org/v1/points/{z}/{x}/{y}.png?taxon_id=, used in an
      # earlier round). That endpoint's marker size has no working query
      # parameter at all -- confirmed live: color/opacity/border_opacity all
      # measurably change the response, but marker-width/width/radius/
      # dot-radius/size all produced byte-identical output to a bare
      # request -- so "iNat markers too large" could not be fixed through
      # that API. Fetched instead as real point data
      # (api.inaturalist.org/v1/observations, the same endpoint
      # TaxaFetch::fetch_inat_occurrences() counts against; confirmed live
      # this public read query needs no auth token) and drawn with
      # leaflet::addCircleMarkers(), sized to match this gadget's own
      # occurrence-point convention exactly (radius=2) instead of a fixed
      # server-side dot size. A later round tried clusterOptions() plus a
      # bigger radius to address "hard to see when zoomed in" -- REVERTED
      # per direct user feedback ("The iNat points were fine before"); the
      # plain, unclustered radius=2 rendering below is the confirmed-good
      # version. Only drawn when a taxon_id is available (reuses the same
      # inat_row() lookup already computed for the sidebar text) -- the
      # sidebar's own iNat line already explains when/why this is absent.
      ir <- inat_row()
      if (!is.null(ir) && !is.null(ir$taxon_id) && !is.na(ir$taxon_id)) {
        inat_pts <- tryCatch(
          .fetch_inat_points(
            ir$taxon_id, lat = query_lat, lng = query_lon, radius_km = inat_radius_km
          ),
          error = function(e) NULL
        )
        if (!is.null(inat_pts) && nrow(inat_pts) > 0L) {
          proxy <- leaflet::addCircleMarkers(
            proxy, lng = inat_pts$lon, lat = inat_pts$lat,
            radius = 2, color = "#16a34a", fillOpacity = 0.7, opacity = 0, weight = 0,
            group = "inat_points"
          )
        }
        # Dashed search-radius boundary, grouped with the points themselves
        # so toggling "inat_points" off/on hides/shows both together --
        # without this, a taxon with no visible points nearby reads as "no
        # iNat data at all" when it may just mean "none within this radius."
        proxy <- leaflet::addCircles(
          proxy, lng = query_lon, lat = query_lat, radius = inat_radius_km * 1000,
          color = "#16a34a", weight = 1.5, opacity = 0.6, fill = FALSE,
          dashArray = "6", group = "inat_points"
        )
      }

      if (!is.null(occurrence_data)) {
        pts <- occurrence_data[
          occurrence_data[[occurrence_taxon_col]] %in% input$taxon &
            !is.na(occurrence_data[[occurrence_lat_col]]) &
            !is.na(occurrence_data[[occurrence_lon_col]]),
          , drop = FALSE
        ]
        if (nrow(pts) > 0L) {
          # Deliberately tiny: GBIF's own density pixels are fine-grained,
          # and even a modest circleMarker (a fixed SCREEN-pixel radius,
          # unlike the tile layer's own pixels which scale with zoom) reads
          # as oversized next to them. weight=0 (no outline) keeps it a
          # plain dot rather than a bordered disc.
          proxy <- leaflet::addCircleMarkers(
            proxy, lng = pts[[occurrence_lon_col]], lat = pts[[occurrence_lat_col]],
            radius = 2, color = "#1d4ed8", fillOpacity = 0.7, opacity = 0, weight = 0,
            group = "occ_points"
          )
        }
      }

      if (!is.null(excluded_occurrence_data)) {
        ex <- excluded_occurrence_data[
          excluded_occurrence_data[[occurrence_taxon_col]] %in% input$taxon &
            !is.na(excluded_occurrence_data[[occurrence_lat_col]]) &
            !is.na(excluded_occurrence_data[[occurrence_lon_col]]),
          , drop = FALSE
        ]
        if (nrow(ex) > 0L) {
          # Hollow red rings, deliberately distinct from the solid blue
          # "kept" points above -- these are GBIF records this study's own
          # quality/outlier/institution/spatial-QC filtering excluded, shown
          # for provenance, not as evidence the taxon is present. Sized down
          # to match the (also shrunk) kept-points overlay.
          proxy <- leaflet::addCircleMarkers(
            proxy, lng = ex[[occurrence_lon_col]], lat = ex[[occurrence_lat_col]],
            radius = 3, color = "#dc2626", fillOpacity = 0, opacity = 0.85, weight = 1.5,
            group = "excluded_points"
          )
        }
      }

      proxy <- leaflet::addMarkers(
        proxy, lng = query_lon, lat = query_lat,
        popup = "Study site", group = "site"
      )

      # Re-issued every taxon change (after the groups above are rebuilt),
      # not just once at initial render -- leaflet's R htmlwidget resolves
      # overlayGroups against whatever layers currently carry that group
      # name, so calling this before a group's first addTiles()/
      # addCircleMarkers() call in a given render would register a
      # checkbox for a group that doesn't exist yet. A repeat call with the
      # same group names updates the existing control in place rather than
      # stacking duplicates. Named explicitly (not "site") so the one
      # always-present study-site marker isn't toggleable clutter.
      proxy <- leaflet::addLayersControl(
        proxy,
        overlayGroups = c("gbif_tiles", "inat_points", "occ_points", "excluded_points"),
        options = leaflet::layersControlOptions(collapsed = FALSE)
      )
    })

    ai_result <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$run_ai, {
      shiny::req(input$taxon, context)
      ai_result(list(pending = TRUE))

      row <- data.frame(.taxon = input$taxon, stringsAsFactors = FALSE)
      g  <- gbif_res()
      ir <- inat_row()
      if (!is.null(g)) {
        row$dist_nearest_occupied_km <- g$dist_nearest_occupied_km
        row$patch_diameter_km        <- g$patch_diameter_km
        row$beyond_buffer            <- g$beyond_buffer
      }
      if (!is.null(ir)) {
        row$in_range        <- ir$in_range
        row$n_observations  <- ir$n_observations
        row$matched_name    <- ir$matched_name
      }

      res <- tryCatch(
        review_assignments(
          input_df = row, taxon_col = ".taxon", context = context,
          target_group = target_group, marker = marker,
          llm_fn = llm_fn, verbose = FALSE
        ),
        error = function(e) {
          ai_result(list(error = conditionMessage(e)))
          NULL
        }
      )
      if (!is.null(res)) ai_result(as.list(res[1L, ]))
    })

    output$ai_panel <- shiny::renderUI({
      r <- ai_result()
      if (is.null(r)) return(NULL)
      if (isTRUE(r$pending)) return(shiny::p("Calling LLM...", style = "font-size:12px;color:#999;"))
      if (!is.null(r$error))
        return(shiny::p(paste("Error:", r$error), style = "font-size:12px;color:#b91c1c;"))

      shiny::tagList(
        shiny::h4("AI Review", style = "margin:6px 0 4px;font-size:13px;"),
        shiny::p(
          sprintf("Geographic: %s | Contamination: %s",
                  r$llm_geographic_plausibility %||% "NA", r$llm_contamination_risk %||% "NA"),
          style = "font-size:12px;margin:2px 0;"
        ),
        if (!is.null(r$review_comment) && !is.na(r$review_comment))
          shiny::p(r$review_comment, style = "font-size:12px;margin:4px 0;font-style:italic;")
        else NULL
      )
    })

    shiny::observeEvent(input$done, {
      shiny::stopApp(returnValue = invisible(NULL))
    })
  }
}


#' Build the GBIF density-tile URL for one taxon/style/bin/year combination
#' Pure/testable: the .point->.poly auto-upgrade + bin=square/squareSize
#' params + Heat-family exclusion, extracted out of the
#' observeEvent(input$taxon) call site. squareSize/bin=square are silent
#' NO-OPS on a bare `.point`-suffixed style -- confirmed live (byte-
#' identical response with/without them) -- and only take effect once the
#' style is switched to its `.poly` counterpart, which is why a bare
#' `.point` style is upgraded here whenever `bin_size` is supplied.
#' Heat-family styles (purpleHeat.point etc.) have no `.poly` counterpart
#' at all and are left unbinned; their own diffuse glow rendering is
#' already visually larger than classic.point's raw single-pixel dots.
#' @noRd
.gbif_tile_url <- function(taxon_key, style, bin_size, year_range) {
  year_q <- if (!is.null(year_range)) sprintf("&year=%s", year_range) else ""
  bin_q <- ""
  if (!is.null(bin_size) && !grepl("Heat\\.point$", style)) {
    if (grepl("\\.point$", style)) style <- sub("\\.point$", ".poly", style)
    bin_q <- sprintf("&bin=square&squareSize=%d", bin_size)
  }
  sprintf(
    "https://api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@1x.png?taxonKey=%d&style=%s%s%s",
    taxon_key, style, year_q, bin_q
  )
}


#' Real, sampled legend gradient + label for a given GBIF style
#' Pure/testable, extracted out of the legend-construction call site.
#' Keyed on the style stripped of its .point/.poly suffix (binning never
#' changes a style's color family). Every gradient stop is real, sampled
#' pixel RGB read directly off a live GBIF tile (a sparse local tile plus
#' a deliberately dense world tile per style, to see each ramp's true top
#' end) -- NOT inferred from a style's name, which was the mistake an
#' earlier round made (guessed "Yellow-Red ramp" colors for "classic" that
#' were wrong, then discovered the same hardcoded guess was being shown
#' regardless of the caller's actual gbif_style at all, most visibly wrong
#' for "purpleHeat.point": real color is black -> purple -> magenta ->
#' pink, nothing resembling yellow at any point). A style outside this
#' verified set gets a neutral gray gradient and a label that says so,
#' rather than another guess.
#' @noRd
.gbif_legend_swatch <- function(style) {
  base <- sub("\\.(point|poly)$", "", style)
  known <- c(
    classic    = "linear-gradient(90deg,#ffff00,#ff9800,#d50a00)",
    purpleHeat = "linear-gradient(90deg,#851284,#ff21fd,#ffadff)",
    greenHeat  = "linear-gradient(90deg,#1d4e0c,#4cb621)",
    blueHeat   = "linear-gradient(90deg,#113a85,#2e8fff,#a9fbff)",
    orangeHeat = "linear-gradient(90deg,#64360d,#d98724,#fff98f)"
  )
  if (base %in% names(known)) {
    list(gradient = known[[base]], label = "GBIF density")
  } else {
    list(
      gradient = "linear-gradient(90deg,#bbbbbb,#555555)",
      label = "GBIF density (colors unverified for this style)"
    )
  }
}


#' Fetch real individual iNaturalist observation points, for map plotting
#' Real point data, not iNaturalist's own raster observation-tile endpoint
#' (see the observeEvent(input$taxon) call site's own comment for why:
#' that endpoint's marker size has no working query parameter, confirmed
#' live). Same underlying /v1/observations search endpoint
#' TaxaFetch::fetch_inat_occurrences() queries -- but NOT a duplicate of it:
#' that function returns one COUNT per taxon (n_observations_local, via
#' per_page=1, reading only total_results), never the individual records
#' themselves, so it structurally cannot supply what map plotting needs
#' (each observation's own lat/lon). Confirmed directly against its source
#' before writing this function, not assumed. A live check separately
#' confirmed this specific read-only, already-public-data query needs no
#' Authorization header, so this stays self-contained in TaxaFlag (httr2,
#' already required) rather than pulling in TaxaFetch as a hard dependency
#' for what would otherwise be a genuinely new, count-vs-points signature on
#' that function. per_page hard-capped at iNat's own real server-side
#' maximum (confirmed live: requesting 201 silently returns 200) -- no
#' pagination beyond one page, matching this gadget's "cheap map context,
#' not a full census" scope. radius_km default 500 (not
#' fetch_inat_occurrences()'s own 50km default) -- confirmed live this is
#' needed, not just a bigger-for-its-own-sake choice: the raster tile layer
#' this replaced always covered the FULL visible map regardless of any
#' radius (it was rendering GBIF-style world density, not a fixed local
#' search), so a real click-through correctly flagged 50km as "a small
#' region" compared to what the gadget used to show -- confirmed live at
#' 500km, real results genuinely spread across a wide area (Iowa/Indiana/
#' Ontario/Wisconsin for a real Chicago-area test point) rather than
#' clustering near the query point, since iNat's own default sort is
#' most-recent-first, not nearest-first.
#' @noRd
.fetch_inat_points <- function(taxon_id, lat, lng, radius_km = 500, per_page = 200L) {
  resp <- httr2::req_perform(
    httr2::req_url_query(
      httr2::request("https://api.inaturalist.org/v1/observations"),
      taxon_id = taxon_id, lat = lat, lng = lng, radius = radius_km,
      per_page = per_page, geo = "true"
    )
  )
  results <- httr2::resp_body_json(resp)$results
  coords <- lapply(results, function(r) r$geojson$coordinates)
  coords <- coords[!vapply(coords, is.null, logical(1))]
  if (length(coords) == 0L) {
    return(data.frame(lon = numeric(0), lat = numeric(0)))
  }
  data.frame(
    lon = vapply(coords, `[[`, numeric(1), 1L),
    lat = vapply(coords, `[[`, numeric(1), 2L)
  )
}


#' Resolve a taxon name to a GBIF backbone usageKey
#' Direct GBIF species-match call -- same endpoint/approach used to develop
#' and verify check_gbif_tile_range() itself; no extra dependency beyond
#' httr2 (already required by this gadget).
#' @noRd
.resolve_gbif_taxon_key <- function(name) {
  resp <- httr2::req_perform(
    httr2::req_url_query(
      httr2::request("https://api.gbif.org/v1/species/match"), name = name
    )
  )
  key <- httr2::resp_body_json(resp)$usageKey
  if (is.null(key)) NA_integer_ else as.integer(key)
}
