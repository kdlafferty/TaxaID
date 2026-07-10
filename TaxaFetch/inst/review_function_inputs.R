# ==============================================================================
# review_function_inputs.R
# TaxaFetch — small, ready-to-run inputs for every exported function
#
# PURPOSE
# -------
# Prepared for external code review: gives the reviewer a concrete, small
# input for each exported function so it can actually be run/tested, without
# having to reverse-engineer arguments from the source or from production
# workflows that fetch 10,000+ records.
#
# Inputs are pulled from three sources, cheapest first:
#   1. Existing testthat fixtures (already validated, fully offline)
#   2. Real small values taken from production workflow scripts elsewhere in
#      the monorepo (kept small/limited deliberately -- see REQUIRES tags)
#   3. New small synthetic inputs constructed for this file where no fixture
#      or workflow example existed
#
# REQUIRES tags (read before running a section):
#   OFFLINE       -- pure function or fully mocked-equivalent input; no network
#   NETWORK       -- hits a public API, no credentials needed (GBIF, PASTA,
#                    iNaturalist, OpenAlex); small/fast by construction here
#   NETWORK+AUTH  -- needs credentials in ~/.Renviron (GBIF_USER/PWD/EMAIL,
#                    OPENALEX_API_KEY) in addition to network access
#   LLM_CALL      -- makes a real, billed call to an LLM provider (needs
#                    ANTHROPIC_API_KEY by default); costs money, keep guarded
#
# Run offline sections freely. For NETWORK/NETWORK+AUTH/LLM_CALL sections,
# either run interactively section-by-section, or flip the RUN_* flags below.
#
# GAP NOTE (see cataloging pass for full detail): screen_pdf_structure(),
# build_pdf_extract_prompt(), parse_pdf_extract_response(), call_api_pdf(),
# extract_pdf_text(), search_dataone(), and fetch_dataone_eml() have zero
# existing test-file coverage in the package; this file is their first
# example input. The PDF-pipeline functions chain off each other (see
# Section 6) and use the two real PDFs already bundled at
# inst/extdata/pdfs/*.pdf.
#
# NON-DETERMINISM NOTE (Section 6, RUN_LLM_CALLS): the whole chain was
# live-verified end to end while preparing this file, but two things vary
# run to run and are not code bugs:
#   - call_api_pdf()'s page rendering occasionally has one of N pages fail
#     in its callr subprocess ("crashed or timed out"); it proceeds with
#     however many rendered successfully. Re-running usually clears it.
#   - the LLM's CSV response occasionally includes a field read.csv() can't
#     parse (e.g. an unescaped embedded comma), which surfaces as a
#     parse_pdf_extract_response() warning + NULL return rather than a
#     crash. Re-running the call_api_pdf() step usually produces valid CSV.
# Three real, reproducible issues WERE found and fixed in this file (not
# LLM variability): the stale package ID in fetch_dataone_eml()'s own
# roxygen @examples (Section 5), the missing explicit LLM provider needed
# for any bare Rscript session (Section 6), and max_tokens=1000L being
# too low for this real 3-image extraction call (Section 6).
# ==============================================================================

devtools::load_all()   # or: library(TaxaFetch)
library(tibble)

# Flip to TRUE to also exercise steps that need credentials or make billed
# LLM calls. Left FALSE by default so a bare run only touches OFFLINE and
# no-credential NETWORK calls.
RUN_GBIF_ACCOUNT_DOWNLOAD <- FALSE   # download_gbif_occurrences() -- needs GBIF_USER/PWD/EMAIL
RUN_OPENALEX_LITERATURE   <- FALSE   # search_literature() / download_literature_pdfs() -- needs OPENALEX_API_KEY
RUN_LLM_CALLS             <- TRUE    # screen_pdf_structure() / call_api_pdf() -- needs ANTHROPIC_API_KEY, costs money


# ==============================================================================
# SECTION 1 -- GBIF pipeline
# make_bbox_wkt() -> get_keys_from_context() -> get_gbif_occurrences()
#   (-> fetch_gbif_occurrences() / download_gbif_occurrences() / fetch_occurrences_by_taxon())
#   -> filter_gbif_quality() -> stack_occurrences() -> report_fetch()
# ==============================================================================

## ---- make_bbox_wkt() ---- OFFLINE, pure function ---------------------------
bbox_wkt <- make_bbox_wkt(lat = 34.5, lon = -120.0, radius_deg = 1.0)
bbox_wkt

## ---- get_keys_from_context() ---- NETWORK, single rgbif::name_backbone() hit
# Fixture reused verbatim from tests/testthat/test-get_keys_from_context.R
hierarchy_full <- data.frame(
  kingdom = "Animalia",
  phylum  = "Chordata",
  class   = "Actinopterygii",
  order   = "Scorpaeniformes",
  family  = "Sebastidae",
  genus   = "Sebastes",
  species = "Sebastes mystinus",
  stringsAsFactors = FALSE
)
keys_result <- get_keys_from_context(hierarchy_full)
keys_result

## ---- fetch_gbif_occurrences() ---- NETWORK, no GBIF account needed ---------
# Real GBIF key + bbox from the package's own live test
# (tests/testthat/test-fetch_gbif_occurrences.R): Engraulis mordax (northern
# anchovy), San Francisco Bay area. That test's own comment notes this can
# still come back 0 rows depending on what's in GBIF right now -- that's
# an accepted outcome (checked there via is.data.frame(), not row count),
# not a broken input.
gbif_key_anchovy <- 2360464L
small_bbox <- make_bbox_wkt(lat = 37.0, lon = -122.5, radius_deg = 2.0)
occ_direct <- fetch_gbif_occurrences(
  keys       = gbif_key_anchovy,
  geometry   = small_bbox,
  year_range = "2010,2024",
  limit      = 20L
)
occ_direct

## ---- download_gbif_occurrences() ---- NETWORK+AUTH -------------------------
# Requires a free GBIF account (GBIF_USER/GBIF_PWD/GBIF_EMAIL in ~/.Renviron).
# Uses the async download API even for small key sets -- expect this to take
# a few minutes (GBIF has to prepare the download job), unlike the direct
# fetch above. Guarded behind RUN_GBIF_ACCOUNT_DOWNLOAD.
if (RUN_GBIF_ACCOUNT_DOWNLOAD) {
  occ_download <- download_gbif_occurrences(
    keys     = gbif_key_anchovy,
    geometry = small_bbox,
    limit    = 20L
  )
  occ_download
}

## ---- get_gbif_occurrences() ---- NETWORK, dispatch wrapper -----------------
# key_threshold default is 50L; one key here always takes the direct-fetch path.
occ_unified <- get_gbif_occurrences(
  keys     = gbif_key_anchovy,
  geometry = small_bbox,
  limit    = 20L
)
occ_unified

## ---- fetch_occurrences_by_taxon() ---- NETWORK ------------------------------
# Real bbox construction pattern from tests/testthat/test-fetch_occurrences_by_taxon.R
box_a <- make_bbox_wkt(lat = 34.40, lon = -120.41, radius_deg = 0.05)
box_b <- make_bbox_wkt(lat = 34.47, lon = -120.36, radius_deg = 0.05)  # overlaps box_a
taxon_geometry_map <- data.frame(
  taxon_key = c(gbif_key_anchovy, gbif_key_anchovy),
  geometry  = c(box_a, box_b),
  stringsAsFactors = FALSE
)
occ_by_taxon <- fetch_occurrences_by_taxon(
  taxon_geometry_map = taxon_geometry_map,
  limit = 20L
)
occ_by_taxon

## ---- filter_gbif_quality() ---- OFFLINE, pure function ----------------------
# Fixture reused verbatim from tests/testthat/test-filter_gbif_quality.R
gbif_like <- data.frame(
  decimalLatitude              = c(34.12, 35.678, NA,    33.0,  36.111, 34.5),
  decimalLongitude             = c(-120.1, -119.5, -118.0, -121.0, -122.0, -120.0),
  basisOfRecord                = c("HUMAN_OBSERVATION", "FOSSIL_SPECIMEN",
                                   "HUMAN_OBSERVATION", "MACHINE_OBSERVATION",
                                   "UNKNOWN", "PRESERVED_SPECIMEN"),
  issues                       = c(NA, "COORDINATE_OUT_OF_RANGE", NA,
                                   "COUNTRY_COORDINATE_MISMATCH", NA, NA),
  coordinateUncertaintyInMeters = c(100, 300, NA, 600, 1000, 50),
  samplingProtocol             = c("net tow", "eDNA water sample", "trawl",
                                   "visual survey", "metabarcoding", "trap"),
  stringsAsFactors = FALSE
)
filtered <- filter_gbif_quality(gbif_like)
filtered

## ---- stack_occurrences() ---- OFFLINE, pure function ------------------------
# Fixture pattern reused from tests/testthat/test-stack_occurrences.R
occ_a <- tibble(
  occurrenceID     = paste0("A", 1:3),
  scientificName   = paste0("Species A", 1:3),
  decimalLatitude  = c(34.0, 34.1, 34.2),
  decimalLongitude = c(-120.0, -120.1, -120.2),
  datasetID        = "test"
)
occ_b <- tibble(
  occurrenceID     = paste0("B", 1:2),
  scientificName   = paste0("Species B", 1:2),
  decimalLatitude  = c(35.0, 35.1),
  decimalLongitude = c(-119.0, -119.1),
  datasetID        = "test"
)
stacked <- stack_occurrences(occ_a, occ_b)
stacked

## ---- report_fetch() ---- OFFLINE, pure function -----------------------------
# Fixture reused from tests/testthat/test-report_fetch.R
occ_for_report <- data.frame(
  scientificName         = c("Sp A", "Sp B", "Sp A"),
  decimalLatitude        = c(34.0, 34.1, 34.2),
  decimalLongitude       = c(-119.0, -119.1, -119.2),
  bibliographicCitation  = c("GBIF Download", "GBIF Download", "GBIF Download"),
  datasetID              = c("gbif:12345", "gbif:12345", "gbif:12345"),
  stringsAsFactors = FALSE
)
fetch_report <- report_fetch(occ_for_report, study_area = "Santa Barbara Channel")
fetch_report


# ==============================================================================
# SECTION 2 -- iNaturalist range check
# ==============================================================================

## ---- check_inat_range() ---- NETWORK, single small taxon -------------------
# Real species used in tests/testthat/test-check_inat_range.R (western sandpiper)
inat_range_result <- check_inat_range(
  taxon_names = "Calidris mauri",
  lat = 34.1,
  lng = -119.1
)
inat_range_result


# ==============================================================================
# SECTION 3 -- BioTime
# ==============================================================================

## ---- read_biotime_study() ---- OFFLINE, synthetic local CSV ----------------
# Same synthetic-CSV pattern as tests/testthat/test-biotime_fetch.R's .bt_tmp()
# helper -- no live BioTime account/download needed.
biotime_csv <- data.frame(
  ABUNDANCE   = c(1, 2, 10, 4),
  BIOMAS      = c(NA, NA, 5.2, NA),
  valid_name  = c("Alloclinus holderi", "Gobiiformes sp",
                  "Alloclinus holderi", "Coryphopterus nicholsii"),
  SAMPLE_DESC = c("2008_11_5_SB-AP", "2008_11_6_SB-CAT",
                  "2004_9_30_SC-PB", "2003_8_7_SC-YB"),
  LATITUDE    = c(33.48, 33.46, 34.03, 33.98),
  LONGITUDE   = c(-119.02, -119.03, -119.70, -119.56),
  DAY         = c(5L, 6L, 30L, 7L),
  MONTH       = c(11L, 11L, 9L, 8L),
  YEAR        = c(2008L, 2008L, 2004L, 2003L),
  stringsAsFactors = FALSE
)
biotime_path <- file.path(tempdir(), "raw_data_595.csv")
utils::write.csv(biotime_csv, biotime_path, row.names = FALSE)

biotime_occ <- read_biotime_study(local_path = biotime_path, study_id = 595)
biotime_occ


# ==============================================================================
# SECTION 4 -- DataONE pipeline, offline half
# build_geo_prompt() / parse_geo_screening_response() and
# build_taxon_screen_prompt() / parse_taxon_screening_response() only need LLM
# response TEXT, not a live LLM call -- both prompt builders and parsers are
# pure functions once you supply the raw_text yourself (as if copy-pasted from
# an LLM chat). Fixtures reused verbatim from
# tests/testthat/test-dataone_standardize.R and
# tests/testthat/test-dataone_taxon_screening_geo.R.
# ==============================================================================

## ---- build_geo_prompt() ---- OFFLINE ----------------------------------------
geo_catalog <- data.frame(
  id                    = c("scope.1.1", "scope.2.1", "other.1.1",
                            "other.2.1", "nodesc.1.1"),
  scope                 = c("knb-lter-sbc", "knb-lter-sbc", "knb-lter-fce",
                            "knb-lter-hfr", "knb-lter-arc"),
  geographicdescription = c("Santa Barbara Channel, California",
                            "Santa Barbara Channel, California",
                            "Florida Everglades",
                            "Harvard Forest, Massachusetts",
                            NA_character_),
  is_candidate          = c(TRUE, TRUE, TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)
sbc_bbox <- c(-120.5, -119.3, 33.8, 34.5)  # c(west, east, south, north)

geo_prompt <- build_geo_prompt(geo_catalog, sbc_bbox, scope_lookup = NULL, verbose = FALSE)
geo_prompt          # exercises print.geo_prompt()

## ---- parse_geo_screening_response() ---- OFFLINE ---------------------------
# raw_text built to match geo_prompt$n_items exactly (however many unique
# descriptions ended up going to the LLM) so this runs regardless of that count.
geo_matches  <- rep(c("YES", "NO"), length.out = geo_prompt$n_items)
geo_raw_text <- paste(
  c("index,match", sprintf("%d,%s", seq_len(geo_prompt$n_items), geo_matches)),
  collapse = "\n"
)
geo_screened <- parse_geo_screening_response(geo_raw_text, geo_prompt)
geo_screened

## ---- build_taxon_screen_prompt() ---- OFFLINE -------------------------------
# Fixture reused from tests/testthat/test-dataone_taxon_screening_geo.R
taxon_catalog <- tibble(
  id          = c("W1", "W2"),
  title       = c("Paper 1", "Paper 2"),
  abstract    = c("Abstract about fish species in California 1",
                  "Abstract about fish species in California 2"),
  keywords    = "fish; ecology; California",
  doi         = c("10.1234/test.1", "10.1234/test.2"),
  pdf_url     = NA_character_,
  year        = 2020L,
  authors     = "Smith J",
  journal     = "Test Journal",
  geo_match   = NA_character_,
  taxon_match = NA_character_
)
taxon_prompt <- build_taxon_screen_prompt(
  catalog     = taxon_catalog,
  taxon_scope = "gobies",
  geo_scope   = "southern California",
  verbose     = FALSE
)
taxon_prompt        # exercises print.taxon_prompt()

## ---- parse_taxon_screening_response() ---- OFFLINE --------------------------
taxon_raw_text <- "index,taxon_match,geo_match\n1,YES,YES\n2,NO,YES"
taxon_screened <- parse_taxon_screening_response(taxon_raw_text, taxon_prompt)
taxon_screened


# ==============================================================================
# SECTION 5 -- DataONE pipeline, live-network half
# All hit the real PASTA/EDI repository (pasta.lternet.edu). No credentials
# needed -- PASTA is a public API. Kept small (max_rows/n_rows capped, single
# known dataset) so this stays fast; production workflows in
# inst/Dataone_workflow.R harvest the FULL catalog (~2-5 min), which this file
# deliberately does not reproduce.
# ==============================================================================

## ---- harvest_dataone_catalog() ---- NETWORK, capped small -------------------
dataone_catalog <- harvest_dataone_catalog(
  cache_file = file.path(tempdir(), "pasta_catalog_review.rds"),
  max_rows   = 50L,
  verbose    = TRUE
)
dataone_catalog

## ---- search_dataone() ---- NETWORK, legacy simple search --------------------
# bbox here is the named-list form this function expects (see its own
# roxygen), not the numeric vector used by build_geo_prompt() above.
dataone_search_result <- search_dataone(
  bbox     = list(west = -120.5, east = -119.3, south = 33.8, north = 34.5),
  keywords = "fish",
  max_rows = 20L
)
dataone_search_result

## ---- fetch_dataone_eml() ---- NETWORK ---------------------------------------
# This function's own roxygen @examples cites "knb-lter-sbc.17.18" -- verified
# while preparing this file that revision no longer resolves (live HTTP 404;
# PASTA packages get revised/retired over time, so a hardcoded @examples ID
# can go stale). Using "edi.885.1" instead -- the same real, confirmed-working
# dataset used in inst/dataone_quickstart.R.
eml_xml <- fetch_dataone_eml("edi.885.1")
substr(eml_xml, 1, 200)   # just show the start; it's a full XML document

## ---- screen_eml_columns() ---- NETWORK --------------------------------------
# Same substitution as fetch_dataone_eml() above, for the same reason.
eml_screen_result <- screen_eml_columns(
  ids  = "edi.885.1",
  bbox = sbc_bbox
)
eml_screen_result

## ---- preview_dataone_occurrences() ---- NETWORK -----------------------------
# Real, small, confirmed-working dataset ID from inst/dataone_quickstart.R
# (SBC LTER kelp forest fish, Darwin Core Archive structure).
dataone_preview <- preview_dataone_occurrences(
  dataset_ids = "edi.885.1",
  bbox        = sbc_bbox,
  n_rows      = 5L
)
dataone_preview    # exercises print.dataone_preview()

## ---- fetch_dataone_occurrences() ---- NETWORK, slower (~2 min) -------------
# Same real dataset as above, full standardize pipeline. This one dataset
# returns ~50k rows even though the call itself is simple -- the only
# "small" input available for this function without inventing a fake PASTA
# package is a small timeout/verbose call against a known-good real dataset.
dataone_occ <- fetch_dataone_occurrences(
  dataset_ids = "edi.885.1",
  bbox        = sbc_bbox,
  timeout     = 120L
)
nrow(dataone_occ)
head(dataone_occ)


# ==============================================================================
# SECTION 6 -- Literature search + PDF pipeline
# search_literature() -> download_literature_pdfs() -> extract_pdf_text()
#   -> screen_pdf_structure() -> build_pdf_extract_prompt() -> call_api_pdf()
#   -> parse_pdf_extract_response()
#
# extract_pdf_text() runs against the two real bundled PDFs at
# inst/extdata/pdfs/*.pdf (OpenAlex works, already shipped with the package --
# no download needed for this step). Everything past screen_pdf_structure()
# needs a real Anthropic API call; guarded behind RUN_LLM_CALLS.
# ==============================================================================

## ---- search_literature() ---- NETWORK+AUTH (OPENALEX_API_KEY) --------------
if (RUN_OPENALEX_LITERATURE) {
  lit_catalog <- search_literature(
    taxon_scope = "gobies",
    geo_scope   = "southern California",
    max_results = 5L
  )
  lit_catalog

  ## ---- download_literature_pdfs() ---- NETWORK+AUTH -------------------------
  lit_pdf_dir <- file.path(tempdir(), "review_lit_pdfs")
  dir.create(lit_pdf_dir, showWarnings = FALSE)
  lit_downloaded <- download_literature_pdfs(
    catalog    = lit_catalog,
    output_dir = lit_pdf_dir,
    max_papers = 1L
  )
  lit_downloaded
}

## ---- extract_pdf_text() ---- OFFLINE (uses bundled real PDF) ---------------
bundled_pdf <- system.file("extdata", "pdfs", "W2403944014.pdf", package = "TaxaFetch")
pdf_text_result <- extract_pdf_text(bundled_pdf)
names(pdf_text_result)
pdf_text_result$n_pages

## ---- screen_pdf_structure() ---- LLM_CALL -----------------------------------
if (RUN_LLM_CALLS) {
  # TaxaFetch/CLAUDE.md's own documented footgun: library(TaxaTools) alone does
  # NOT activate provider auto-detection in a plain Rscript session (only in
  # RStudio) -- call_api()'s default llm_fn then errors "no LLM provider
  # configured" even with a real ANTHROPIC_API_KEY set. Verified live while
  # preparing this file. Workaround per CLAUDE.md: pass an explicit provider.
  review_llm_fn <- function(prompt, ...) {
    TaxaTools::call_api(prompt, ..., provider = "anthropic")
  }

  pdf_structure <- screen_pdf_structure(
    pdf_text_result,
    llm_fn     = review_llm_fn,
    max_tokens = 400L
  )
  pdf_structure        # exercises print.pdf_structure()

  ## ---- build_pdf_extract_prompt() ---- OFFLINE once pdf_structure exists ----
  # For this bundled PDF, the real LLM classification comes back
  # single_site_rule = TRUE (a single-site field survey), which
  # build_pdf_extract_prompt() correctly refuses to proceed on without
  # single_site_coords -- it needs somewhere to inject the site's lat/lon
  # into the extraction prompt since the paper itself may not repeat
  # coordinates on every occurrence row. In real use this comes from the
  # paper's own stated site location; a placeholder value is supplied here
  # only so this example input runs standalone.
  pdf_extract_prompt <- build_pdf_extract_prompt(
    pdf_structure,
    single_site_coords = list(lat = 34.4, lon = -119.7)
  )
  pdf_extract_prompt  # exercises print.pdf_extract_prompt()

  ## ---- call_api_pdf() ---- LLM_CALL, vision API -----------------------------
  # provider = "anthropic" for the same reason as review_llm_fn above --
  # call_api_pdf()'s own provider/model default resolution goes through the
  # same call_api() auto-detection path.
  # max_tokens: verified live while preparing this file that 1000L (an
  # attempt to shrink the function's own 4000L default for a "small" example)
  # reproducibly makes the real 3-image extraction prompt below come back as
  # "call_api (anthropic): response contained no text blocks" -- the model's
  # full CSV response for this real paper needs more headroom than 1000
  # tokens. 2000L is confirmed working against this exact bundled PDF.
  pdf_api_raw <- call_api_pdf(
    prompt     = pdf_extract_prompt$prompts[[1]],
    pdf_path   = bundled_pdf,
    provider   = "anthropic",
    max_tokens = 2000L
  )
  pdf_api_raw

  ## ---- parse_pdf_extract_response() ---- OFFLINE ----------------------------
  pdf_extracted <- parse_pdf_extract_response(pdf_api_raw, pdf_extract_prompt)
  pdf_extracted
}
