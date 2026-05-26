# ==============================================================================
# pdf_workflow_test_v4.R
# TaxaFetch — Literature search + PDF extraction full workflow
#
# Stages:
#   Stage 0  — Clean session + reload; check API keys
#   Stage 1  — Define scope: taxon_scope, geo_scope, bbox
#   Stage 2  — search_literature()            OpenAlex catalog harvest
#   Stage 3  — Inspect catalog
#   Stage 4  — [OPTIONAL] Combined taxon + geo screening
#   Stage 5  — Inspect screened catalog; decide which papers to download
#   Stage 6  — download_literature_pdfs()     fetch PDFs to local dir
#   Stage 7  — extract_pdf_text()             section detection (no API)
#   Stage 8  — screen_pdf_structure()         five-axis characterisation
#   Stage 9  — Inspect structures; drop non-extractable paper types
#   Stage 10 — build_pdf_extract_prompt()     configure extraction prompt
#   Stage 11 — API call(s) — extraction       call_api_pdf()
#   Stage 12 — parse_pdf_extract_response()   DwC tibble per paper
#   Stage 13 — stack_occurrences()            combine all papers
#
# Run section-by-section in RStudio (Cmd+Enter or Ctrl+Enter).
#
# Required environment variables (~/.Renviron):
#   ANTHROPIC_API_KEY   — for Stages 8, 11
#   OPENALEX_API_KEY    — for Stage 2 (free; see openalex.org/settings/api)
#
# Checkpoint files written:
#   openalex_catalog.rds      Stage 2  — refresh when scope/bbox changes
#   taxon_screened.rds        Stage 4  — optional
#   downloaded_catalog.rds    Stage 6
#   pdf_structures.rds        Stage 8
#   pdf_raw_responses.rds     Stage 11 (expensive — always checkpoint)
#   pdf_occ_list.rds          Stage 12
#
# Resuming from a checkpoint:
#   Uncomment the readRDS() line for the stage you want to resume from,
#   then run from that stage onward. Do NOT re-run earlier stages unless
#   you want to redo those API calls.
#
# DataONE parallel reference: PDF_PIPELINE_DATAONE_PARALLEL.md
# Session history: Session 25 (v4 — literature search integrated, bug fixes)
# ==============================================================================


# ==============================================================================
# STAGE 0 — Clean session + reload; check API keys
# ==============================================================================
library(TaxaFetch)
rm(list = ls())
devtools::load_all()

for (pkg in c("pdftools", "png", "base64enc")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(sprintf("Installing missing dependency: %s", pkg))
    install.packages(pkg)
  }
}

if (!nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
  stop(
    "ANTHROPIC_API_KEY not found.\n",
    "Add it to ~/.Renviron (usethis::edit_r_environ()), then restart R."
  )
}
if (!nzchar(Sys.getenv("OPENALEX_API_KEY"))) {
  stop(
    "OPENALEX_API_KEY not found.\n",
    "Getting one is free (30 seconds):\n",
    "  1. Create an account at openalex.org\n",
    "  2. Copy your key from openalex.org/settings/api\n",
    "  3. Add OPENALEX_API_KEY=your_key to ~/.Renviron, then restart R.\n",
    "Your free key provides $1 of usage per day."
  )
}
message("Both API keys found.")


# ==============================================================================
# STAGE 1 — Define scope
#
# taxon_scope — drives the OpenAlex full-text search AND the LLM taxon screen.
#   Include formal names + common names for best recall:
#     "gobies, goby, Gobiidae, tidewater goby, Eucyclogobius"
#   A narrow single word like "gobies" may miss papers that use Latin names.
#
# geo_scope   — plain-language study area for the Stage 4 LLM screen.
#   Not used in the OpenAlex query (Nominatim handles geographic pre-filtering);
#   used only by the combined taxon+geo LLM screening in Stage 4.
#
# bbox        — c(lon_min, lon_max, lat_min, lat_max)
#   Centroid and corners are reverse-geocoded via Nominatim to extract
#   county/state names as geographic AND-filters for the OpenAlex query.
#   If all points fall offshore, geographic pre-filtering is skipped and
#   you should run Stage 4 geo screening to compensate.
# ==============================================================================

taxon_scope <- "gobies, goby, Gobiidae, tidewater goby, Eucyclogobius"

geo_scope <- "southern California, Santa Barbara, coastal waters"

bbox <- c(
  lon_min = -119.5,
  lon_max = -117.0,
  lat_min =   33.5,
  lat_max =   34.5
)

pdf_dir <- "pdfs/so_cal_gobies"

message(sprintf("Taxon scope : %s", taxon_scope))
message(sprintf("Geo scope   : %s", geo_scope))
message(sprintf("bbox        : lon [%.2f, %.2f]  lat [%.2f, %.2f]",
                bbox[1], bbox[2], bbox[3], bbox[4]))


# ==============================================================================
# STAGE 2 — Harvest OpenAlex catalog
#
# search_literature():
#   1. Reverse-geocodes bbox corners via Nominatim to extract county/state names
#   2. Builds OpenAlex query: taxon_scope AND geo_terms as separate
#      title_and_abstract.search filters (AND-combined)
#   3. Paginates results cursor-based, sorted by relevance
#   4. Returns catalog tibble matching harvest_dataone_catalog() column structure
#      so Stage 4 screening functions work unchanged
#
# cache_dir: re-running with the same scope+bbox loads from disk, not the API.
# Delete openalex_cache/ to force a fresh query.
# ==============================================================================

openalex_catalog <- search_literature(
  taxon_scope = taxon_scope,
  geo_scope   = geo_scope,
  bbox        = bbox,
  max_results = 200L,
  from_year   = 2000L,
  open_access = TRUE,
  cache_dir   = "openalex_cache",
  verbose     = TRUE
)

saveRDS(openalex_catalog, "openalex_catalog.rds")
# openalex_catalog <- readRDS("openalex_catalog.rds")   # resume line


# ==============================================================================
# STAGE 3 — Inspect catalog
# ==============================================================================

message(sprintf("\nCatalog: %d papers returned.", nrow(openalex_catalog)))

cat("\n--- YEAR DISTRIBUTION ---\n")
print(table(openalex_catalog$year, useNA = "ifany"))

cat("\n--- JOURNAL DISTRIBUTION (top 10) ---\n")
print(head(sort(table(openalex_catalog$journal), decreasing = TRUE), 10L))

cat("\n--- PDF URL AVAILABILITY ---\n")
cat(sprintf("  With pdf_url    : %d / %d\n",
            sum(!is.na(openalex_catalog$pdf_url)), nrow(openalex_catalog)))

cat("\n--- QUERY PARAMETERS ---\n")
cat(sprintf("  taxon_scope : %s\n", taxon_scope))
cat(sprintf("  geo_scope   : %s\n", geo_scope %||% "(none)"))
cat(sprintf("  from_year   : %s\n", if (exists("from_year") && !is.null(from_year)) from_year else "(none)"))

cat("\n--- ALL TITLES ---\n")
for (i in seq_len(nrow(openalex_catalog))) {
  cat(sprintf("  [%d] %s (%s)\n",
              i,
              substr(openalex_catalog$title[i], 1L, 90L),
              openalex_catalog$year[i]))
}

# Inspect a specific abstract — useful for debugging screening decisions:
# cat(openalex_catalog$abstract[1])


# ==============================================================================
# STAGE 4 — [OPTIONAL] Combined taxon + geo screening
#
# Uses build_taxon_screen_prompt() with geo_scope to assess both taxon and
# geographic relevance in a single LLM call. Returns taxon_match (logical)
# and geo_match (logical) columns.
#
# For the literature path this replaces the separate build_geo_prompt() step,
# which requires DataONE-specific columns not present in the OpenAlex catalog.
#
# When to run:
#   - Catalog has >10 papers and titles suggest mixed relevance
#   - Geo terms from Nominatim were absent (offshore bbox) so Stage 2 did
#     no geographic pre-filtering
#
# When to skip (run_taxon_screen <- FALSE):
#   - Catalog is small and you have reviewed all titles in Stage 3
#   - taxon_scope was specific enough that results look clean
#
# DEBUGGING TIPS:
#   cat(taxon_prompt$prompts[[1]])   — see full prompt sent to LLM
#   cat(taxon_raw)                   — see raw LLM response before parsing
#   print(taxon_screened[, c("title", "taxon_match", "geo_match")])
#   If a relevant paper was rejected, the key species name may have appeared
#   after the abstract_chars cutoff — increase abstract_chars and re-run.
# ==============================================================================

run_taxon_screen <- FALSE   # set TRUE to enable

if (run_taxon_screen) {

  # Drop any stale screening columns left by a previous run
  openalex_catalog <- openalex_catalog |>
    dplyr::select(-dplyr::any_of(c("taxon_match", "taxon_source", "geo_match")))

  taxon_prompt <- build_taxon_screen_prompt(
    catalog        = openalex_catalog,
    taxon_scope    = taxon_scope,
    geo_scope      = geo_scope,
    chunk_size     = 50L,
    abstract_chars = 2000L,   # higher than DataONE default — lit abstracts are long
    verbose        = TRUE
  )

  # Uncomment to inspect the full prompt before submitting:
  # cat(taxon_prompt$prompts[[1]])

  taxon_raw <- prompt_api(taxon_prompt)

  # Always inspect raw response — catches format problems before parse
  cat("\n--- LLM RAW RESPONSE ---\n")
  cat(taxon_raw, "\n")

  taxon_screened <- parse_taxon_screening_response(taxon_raw, taxon_prompt)

  saveRDS(taxon_screened, "taxon_screened.rds")
  # taxon_screened <- readRDS("taxon_screened.rds")   # resume line

  cat("\n--- SCREENING DECISIONS ---\n")
  print(taxon_screened[, intersect(
    c("title", "taxon_match", "geo_match", "taxon_source"),
    names(taxon_screened)
  )])

  n_pass <- sum(taxon_screened$taxon_match & taxon_screened$geo_match,
                na.rm = TRUE)
  message(sprintf("Screening: %d / %d passed (taxon AND geo match).",
                  n_pass, nrow(taxon_screened)))

  working_catalog <- taxon_screened[
    taxon_screened$taxon_match & taxon_screened$geo_match, ]

} else {
  message("Stage 4: screening skipped — using full catalog.")
  working_catalog <- openalex_catalog
}


# ==============================================================================
# STAGE 5 — Inspect screened catalog; decide what to download
#
# Each PDF download + API extraction costs time and money.
# Review the list, then set n_to_download conservatively.
# Start with 5-10 to test the pipeline end-to-end before scaling up.
# ==============================================================================

cat("\n--- WORKING CATALOG ---\n")
cat(sprintf("  Total papers    : %d\n", nrow(working_catalog)))
n_with_url <- sum(!is.na(working_catalog$pdf_url))
cat(sprintf("  With pdf_url    : %d  (auto-downloadable)\n", n_with_url))
cat(sprintf("  Without pdf_url : %d  (manual download needed)\n",
            nrow(working_catalog) - n_with_url))

cat("\n--- DOWNLOADABLE PAPERS ---\n")
has_url <- working_catalog[!is.na(working_catalog$pdf_url), ]
for (i in seq_len(nrow(has_url))) {
  cat(sprintf("  [%d] %s (%s)\n",
              i,
              substr(has_url$title[i], 1L, 90L),
              has_url$year[i]))
}

# Adjust as needed — start small
n_to_download <- min(10L, n_with_url)
message(sprintf("\nPlan: downloading first %d paper(s).", n_to_download))


# ==============================================================================
# STAGE 6 — Download PDFs
#
# download_literature_pdfs() tries to fetch each pdf_url automatically.
# Many publishers block automated downloads (HTTP 403) even for open-access
# papers. When that happens, download manually via the browser and place the
# PDF in pdf_dir — the manual path below picks it up automatically.
#
# AUTOMATED PATH (runs first):
#   download_literature_pdfs() adds local_pdf_path to the catalog tibble.
#   Skips existing files (overwrite = FALSE).
#   Validates PDF magic bytes — warns and skips invalid downloads.
#
# MANUAL PATH (use when automated download returns HTTP 403):
#   1. Run: browseURL(working_catalog$pdf_url[i])  to open in browser
#   2. Save the PDF to pdf_dir with any filename ending in .pdf
#   3. The pdf_paths block at the end picks up all PDFs in pdf_dir
# ==============================================================================

if (!dir.exists(pdf_dir)) dir.create(pdf_dir, recursive = TRUE)

downloaded_catalog <- download_literature_pdfs(
  catalog    = working_catalog,
  output_dir = pdf_dir,
  overwrite  = FALSE,
  max_papers = n_to_download,
  pause_s    = 0.5,
  verbose    = TRUE
)

saveRDS(downloaded_catalog, "downloaded_catalog.rds")
# downloaded_catalog <- readRDS("downloaded_catalog.rds")   # resume line

# --- Manual download helper ---
# If automated download failed, open URLs in browser one at a time:
# for (i in seq_len(nrow(working_catalog))) {
#   cat(sprintf("[%d] %s\n    %s\n\n", i,
#               working_catalog$title[i],
#               working_catalog$pdf_url[i]))
# }
# browseURL(working_catalog$pdf_url[1])   # open paper 1 in browser

# Collect all PDFs present in pdf_dir — both auto-downloaded and manually placed
pdf_paths <- list.files(pdf_dir, pattern = "\\.pdf$", full.names = TRUE)
message(sprintf("\n%d PDF(s) found in %s:", length(pdf_paths), pdf_dir))
for (p in pdf_paths) {
  info <- tryCatch(pdftools::pdf_info(p), error = function(e) NULL)
  if (!is.null(info)) {
    message(sprintf("  %-60s  %d pages", basename(p), info$pages))
  } else {
    message(sprintf("  %-60s  (could not read — may not be a valid PDF)", basename(p)))
  }
}

if (length(pdf_paths) == 0L) {
  stop(
    "No PDFs found in '", pdf_dir, "'.\n",
    "  Either the automated download failed (check warnings above) or\n",
    "  no papers were in the working catalog.\n",
    "  To download manually: browseURL(working_catalog$pdf_url[1])\n",
    "  then save the PDF to '", pdf_dir, "' and re-run from this stage.",
    call. = FALSE
  )
}

# ==============================================================================
# STAGE 7 — Extract text and detect sections
#
# Cheap — no API call. Reads text via pdftools, detects section headers,
# trims back matter via document boundary detection.
# The pdf_path stored inside each pdf_content object propagates downstream
# to pdf_structure and extract_prompt automatically.
# ==============================================================================

pdf_contents <- lapply(pdf_paths, function(p) {
  message(sprintf("Extracting text: %s", basename(p)))
  tryCatch(
    extract_pdf_text(pdf_path = p, sections = "all", verbose = FALSE),
    error = function(e) {
      warning(sprintf("extract_pdf_text failed for '%s': %s",
                      basename(p), conditionMessage(e)), call. = FALSE)
      NULL
    }
  )
})
names(pdf_contents) <- basename(pdf_paths)

n_ok <- sum(!vapply(pdf_contents, is.null, logical(1L)))
message(sprintf("Text extraction: %d / %d succeeded.", n_ok, length(pdf_paths)))


# ==============================================================================
# STAGE 8 — Characterise paper structure (one cheap LLM call per paper)
#
# Five-axis classification: observation_type, location_structure, data_density,
# taxonomic_scope, contamination_risk. Also builds page_table (send_image
# flags) and abbreviation_inventory used in Stage 10.
# Checkpoint here — Stage 11 API calls are expensive.
# ==============================================================================

pdf_contents_ok <- Filter(Negate(is.null), pdf_contents)

pdf_structures <- lapply(pdf_contents_ok, function(pc) {
  message(sprintf("Characterising: %s", basename(pc$pdf_path)))
  tryCatch(
    screen_pdf_structure(pdf_content = pc, use_llm = TRUE, verbose = FALSE),
    error = function(e) {
      warning(sprintf("screen_pdf_structure failed for '%s': %s",
                      basename(pc$pdf_path), conditionMessage(e)), call. = FALSE)
      NULL
    }
  )
})
names(pdf_structures) <- names(pdf_contents_ok)

saveRDS(pdf_structures, "pdf_structures.rds")
# pdf_structures <- readRDS("pdf_structures.rds")   # resume line

n_ok <- sum(!vapply(pdf_structures, is.null, logical(1L)))
message(sprintf("Characterisation: %d / %d succeeded.", n_ok,
                length(pdf_structures)))


# ==============================================================================
# STAGE 9 — Inspect structures; review extraction decisions
#
# Papers with observation_type = "analytical_modelling" or "experimental_lab"
# return NULL from build_pdf_extract_prompt() and are skipped automatically.
# Papers with send > 30 pages at dpi=150 risk HTTP 429 — dpi=100 or chunking
# is applied automatically in Stage 10 based on page count.
# ==============================================================================

cat("\n--- STRUCTURE SUMMARY ---\n")
for (nm in names(pdf_structures)) {
  ps <- pdf_structures[[nm]]
  if (is.null(ps)) {
    cat(sprintf("  %-55s  [FAILED]\n", nm))
    next
  }
  n_send <- sum(ps$page_table$send_image)
  cat(sprintf(
    "  %-55s  obs=%-22s  loc=%-18s  send=%d%s\n",
    nm,
    ps$observation_type   %||% "?",
    ps$location_structure %||% "?",
    n_send,
    if (n_send > 30L) "  [!] large — dpi=100 will be used" else ""
  ))
}

# Full detail for a specific paper (uncomment and set name):
# print(pdf_structures[["your_paper.pdf"]])


# ==============================================================================
# STAGE 10 — Build extraction prompts
#
# dpi and chunk_pages are set automatically based on page count:
#   n_send > 30  → dpi = 100 (reduces payload to avoid HTTP 429)
#   n_send > 25  → chunk_pages = TRUE (splits into chunks of ≤25 pages)
# ==============================================================================

pdf_structures_ok <- Filter(Negate(is.null), pdf_structures)

extract_prompts <- lapply(pdf_structures_ok, function(ps) {
  n_send      <- sum(ps$page_table$send_image)
  dpi         <- if (n_send > 30L) 100L else 150L
  chunk_pages <- n_send > 25L
  tryCatch(
    build_pdf_extract_prompt(
      pdf_structure = ps,
      dpi           = dpi,
      chunk_pages   = chunk_pages,
      verbose       = TRUE
    ),
    error = function(e) {
      warning(sprintf("build_pdf_extract_prompt failed for '%s': %s",
                      ps$pdf_path, conditionMessage(e)), call. = FALSE)
      NULL
    }
  )
})
names(extract_prompts) <- names(pdf_structures_ok)

cat("\n--- EXTRACTION PROMPT SUMMARY ---\n")
for (nm in names(extract_prompts)) {
  ep <- extract_prompts[[nm]]
  if (is.null(ep)) {
    cat(sprintf("  %-55s  skipped (non-extractable type)\n", nm))
  } else {
    cat(sprintf("  %-55s  %d chunk(s), %d pages, dpi=%d\n",
                nm, ep$n_chunks, ep$n_send, ep$dpi))
  }
}


# ==============================================================================
# STAGE 11 — API extraction calls  [EXPENSIVE — always checkpointed]
#
# Loops over papers and chunks. Multi-chunk responses are concatenated into
# a single string before parsing (parse_pdf_extract_response expects one
# character string regardless of chunking).
#
# Resume after interruption:
#   pdf_raw_responses <- readRDS("pdf_raw_responses.rds")
#   (then skip to Stage 12)
# ==============================================================================

extract_prompts_ok <- Filter(Negate(is.null), extract_prompts)

pdf_raw_responses <- lapply(
  names(extract_prompts_ok),
  function(nm) {
    ep <- extract_prompts_ok[[nm]]
    ps <- pdf_structures_ok[[nm]]
    message(sprintf("API extraction: %s  (%d chunk(s), %d pages, dpi=%d) ...",
                    nm, ep$n_chunks, ep$n_send, ep$dpi))

    chunk_resps <- lapply(seq_len(ep$n_chunks), function(j) {
      if (ep$n_chunks > 1L) {
        message(sprintf("  Chunk %d / %d (pages %d-%d) ...",
                        j, ep$n_chunks,
                        min(ep$page_chunks[[j]]),
                        max(ep$page_chunks[[j]])))
      }
      page_map_j <- list(selected = ep$page_chunks[[j]])
      attr(page_map_j, "has_headers") <- TRUE
      tryCatch(
        call_api_pdf(
          prompt   = ep$prompts[[j]],
          pdf_path = ps$pdf_path,
          sections = "all",
          page_map = page_map_j,
          dpi      = ep$dpi,
          verbose  = FALSE
        ),
        error = function(e) {
          warning(sprintf("  Chunk %d/%d failed for '%s': %s",
                          j, ep$n_chunks, nm, conditionMessage(e)),
                  call. = FALSE)
          NULL
        }
      )
    })

    if (any(vapply(chunk_resps, is.null, logical(1L)))) {
      warning(sprintf("One or more chunks failed for '%s'; skipping.", nm),
              call. = FALSE)
      return(NULL)
    }

    paste(chunk_resps, collapse = "\n")
  }
)
names(pdf_raw_responses) <- names(extract_prompts_ok)

saveRDS(pdf_raw_responses, "pdf_raw_responses.rds")
# pdf_raw_responses <- readRDS("pdf_raw_responses.rds")   # resume line

n_ok <- sum(!vapply(pdf_raw_responses, is.null, logical(1L)))
message(sprintf("API extraction: %d / %d succeeded.", n_ok,
                length(pdf_raw_responses)))

# Inspect raw response for a specific paper (uncomment):
# cat(pdf_raw_responses[["your_paper.pdf"]])


# ==============================================================================
# STAGE 12 — Parse extraction responses to DwC tibbles
# ==============================================================================

pdf_occ_list <- lapply(
  names(pdf_raw_responses),
  function(nm) {
    raw <- pdf_raw_responses[[nm]]
    ep  <- extract_prompts_ok[[nm]]
    if (is.null(raw) || is.null(ep)) return(NULL)
    message(sprintf("Parsing: %s", nm))
    tryCatch(
      parse_pdf_extract_response(raw_text = raw, extract_prompt = ep),
      error = function(e) {
        warning(sprintf("  parse failed for '%s': %s", nm,
                        conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
  }
)
names(pdf_occ_list) <- names(pdf_raw_responses)

saveRDS(pdf_occ_list, "pdf_occ_list.rds")
# pdf_occ_list <- readRDS("pdf_occ_list.rds")   # resume line

pdf_occ_list_clean <- Filter(Negate(is.null), pdf_occ_list)
message(sprintf("Parsing: %d / %d papers produced occurrence records.",
                length(pdf_occ_list_clean), length(pdf_occ_list)))

for (nm in names(pdf_occ_list_clean)) {
  message(sprintf("  %-55s  %d records", nm, nrow(pdf_occ_list_clean[[nm]])))
}

# Inspect records for a specific paper (uncomment):
# print(pdf_occ_list_clean[["your_paper.pdf"]])


# ==============================================================================
# STAGE 13 — Stack results
#
# stack_occurrences() row-binds per-paper tibbles, adds point_id, reports
# record counts per source. Compatible with downstream habitat assignment,
# spatial QAQC, and combination with DataONE/GBIF via stack_occurrences().
# ==============================================================================

if (length(pdf_occ_list_clean) == 0L) {
  message("No occurrence records to stack.")
} else {

  all_pdf_occ <- stack_occurrences(pdf_occ_list_clean)

  message(sprintf("\nTotal occurrence records: %d", nrow(all_pdf_occ)))

  cat("\n--- COLUMNS ---\n")
  cat(paste(names(all_pdf_occ), collapse = "\n"), "\n")

  cat("\n--- UNIQUE TAXA (first 20) ---\n")
  print(head(sort(unique(all_pdf_occ$scientificName)), 20L))

  cat("\n--- COORDINATE SUMMARY ---\n")
  n_coords <- sum(!is.na(all_pdf_occ$decimalLatitude))
  cat(sprintf("  Records with coordinates : %d / %d\n",
              n_coords, nrow(all_pdf_occ)))
  if (n_coords > 0L) {
    cat(sprintf("  Lat range : %.4f to %.4f\n",
                min(all_pdf_occ$decimalLatitude, na.rm = TRUE),
                max(all_pdf_occ$decimalLatitude, na.rm = TRUE)))
    cat(sprintf("  Lon range : %.4f to %.4f\n",
                min(all_pdf_occ$decimalLongitude, na.rm = TRUE),
                max(all_pdf_occ$decimalLongitude, na.rm = TRUE)))
  }

  # Combine with DataONE or GBIF output (uncomment when merging pipelines):
  # all_occ <- stack_occurrences(list(all_pdf_occ, dataone_occ))
  # message(sprintf("Combined (PDF + DataONE): %d records.", nrow(all_occ)))
}
