# ==============================================================================
# IUCN Red List Habitat Classification v3.1 -- internal lookup table
#
# Source: IUCN Standards and Petitions Committee (2022).
# https://www.iucnredlist.org/resources/habitat-classification-scheme
#
# Columns:
#   l1_code  -- Level 1 numeric code (character, e.g. "9")
#   l1_name  -- Level 1 label (e.g. "Marine Neritic")
#   l2_code  -- Level 2 numeric code (character, e.g. "9.1")
#   l2_name  -- Level 2 label (e.g. "Seagrass (submerged)"); NA for the four
#               L1 groups that have no real L2 subcategories in the source
#               scheme (Rocky Areas (inland), Introduced Vegetation, Other,
#               Unknown)
#
# Audited row-by-row against the source document 2026-08-01 after a code
# review flagged 1.3/3.3 as mislabeled "Subalpine" (should be "Subantarctic"/
# "Boreal" respectively) and asked whether the pattern continued elsewhere.
# It did: Shrubland's whole 3.1-3.3 order was wrong (real order is Subarctic/
# Subantarctic/Boreal, not Forest's Boreal/Subarctic/Subantarctic order);
# Grassland's 4.3 was "Subalpine/Alpine" instead of "Subantarctic"; the whole
# Marine Neritic (9.x) block was scrambled with several fabricated entries;
# Marine Deep Ocean Floor was missing "Seamount" (real 11.5) entirely and had
# a wrong Hadal-zone depth threshold; Wetlands (Inland) had a fabricated 19th
# entry and a fabricated 5.18; Artificial - Aquatic had three fabricated
# entries (15.10-15.12) and was missing the real 15.13; Rocky Areas (inland),
# Introduced Vegetation, Other, and Unknown all had fabricated L2
# subcategories despite being L1-only in the real scheme. See each inline
# comment below for the specific fix. Verified against the real IUCN Habitats
# Classification Scheme v3.1 source document (fetched directly, not from
# memory) before any value below was changed.
# ==============================================================================

.iucn_habitat_lookup <- data.frame(
  l1_code = c(
    # 1. Forest & Woodland (9 subcategories)
    rep("1", 9),
    # 2. Savanna (2)
    rep("2", 2),
    # 3. Shrubland (8)
    rep("3", 8),
    # 4. Native Grassland (7)
    rep("4", 7),
    # 5. Wetlands (Inland) (18)
    rep("5", 18),
    # 6. Rocky Areas (Inland) -- L1-only in the real scheme, no L2 subcategories
    rep("6", 1),
    # 7. Caves and Subterranean Habitats (2)
    rep("7", 2),
    # 8. Desert (3)
    rep("8", 3),
    # 9. Marine Neritic (10)
    rep("9", 10),
    # 10. Marine Oceanic (4)
    rep("10", 4),
    # 11. Marine Deep Ocean Floor (Benthic and Demersal) (6)
    rep("11", 6),
    # 12. Marine Intertidal (7)
    rep("12", 7),
    # 13. Marine Coastal/Supratidal (5)
    rep("13", 5),
    # 14. Artificial - Terrestrial (6)
    rep("14", 6),
    # 15. Artificial - Aquatic (13)
    rep("15", 13),
    # 16. Introduced Vegetation -- L1-only, no L2 subcategories
    rep("16", 1),
    # 17. Other -- L1-only, no L2 subcategories
    rep("17", 1),
    # 18. Unknown -- L1-only, no L2 subcategories
    rep("18", 1)
  ),
  l1_name = c(
    rep("Forest", 9),
    rep("Savanna", 2),
    rep("Shrubland", 8),
    rep("Grassland", 7),
    rep("Wetlands (inland)", 18),
    rep("Rocky Areas (inland)", 1),
    rep("Caves and Subterranean Habitats", 2),
    rep("Desert", 3),
    rep("Marine Neritic", 10),
    rep("Marine Oceanic", 4),
    rep("Marine Deep Ocean Floor", 6),
    rep("Marine Intertidal", 7),
    rep("Marine Coastal/Supratidal", 5),
    rep("Artificial - Terrestrial", 6),
    rep("Artificial - Aquatic", 13),
    rep("Introduced Vegetation", 1),
    rep("Other", 1),
    rep("Unknown", 1)
  ),
  l2_code = c(
    # Forest
    "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "1.8", "1.9",
    # Savanna
    "2.1", "2.2",
    # Shrubland
    "3.1", "3.2", "3.3", "3.4", "3.5", "3.6", "3.7", "3.8",
    # Grassland
    "4.1", "4.2", "4.3", "4.4", "4.5", "4.6", "4.7",
    # Wetlands (inland)
    "5.1", "5.2", "5.3", "5.4", "5.5", "5.6", "5.7", "5.8", "5.9",
    "5.10", "5.11", "5.12", "5.13", "5.14", "5.15", "5.16", "5.17", "5.18",
    # Rocky Areas (inland) -- no L2 code in the real scheme
    NA_character_,
    # Caves
    "7.1", "7.2",
    # Desert
    "8.1", "8.2", "8.3",
    # Marine Neritic
    "9.1", "9.2", "9.3", "9.4", "9.5", "9.6", "9.7", "9.8", "9.9", "9.10",
    # Marine Oceanic
    "10.1", "10.2", "10.3", "10.4",
    # Marine Deep Ocean Floor
    "11.1", "11.2", "11.3", "11.4", "11.5", "11.6",
    # Marine Intertidal
    "12.1", "12.2", "12.3", "12.4", "12.5", "12.6", "12.7",
    # Marine Coastal/Supratidal
    "13.1", "13.2", "13.3", "13.4", "13.5",
    # Artificial - Terrestrial
    "14.1", "14.2", "14.3", "14.4", "14.5", "14.6",
    # Artificial - Aquatic
    "15.1", "15.2", "15.3", "15.4", "15.5", "15.6",
    "15.7", "15.8", "15.9", "15.10", "15.11", "15.12", "15.13",
    # Introduced Vegetation -- no L2 code in the real scheme
    NA_character_,
    # Other -- no L2 code in the real scheme
    NA_character_,
    # Unknown -- no L2 code in the real scheme
    NA_character_
  ),
  l2_name = c(
    # Forest
    "Boreal", "Subarctic", "Subantarctic",
    "Temperate", "Subtropical/Tropical Dry",
    "Subtropical/Tropical Moist Lowland",
    "Subtropical/Tropical Mangrove Above High Tide",
    "Subtropical/Tropical Swamp",
    "Subtropical/Tropical Moist Montane",
    # Savanna
    "Dry", "Moist",
    # Shrubland -- NOTE: the real IUCN order for Shrubland's first three
    # subcategories is Subarctic/Subantarctic/Boreal, NOT the Boreal/
    # Subarctic/Subantarctic order Forest uses. Verified directly against
    # the IUCN Habitats Classification Scheme v3.1 source document.
    "Subarctic", "Subantarctic", "Boreal", "Temperate",
    "Subtropical/Tropical Dry", "Subtropical/Tropical Moist",
    "Subtropical/Tropical High Altitude",
    "Mediterranean-type Shrubby Vegetation",
    # Grassland
    "Tundra", "Subarctic", "Subantarctic", "Temperate",
    "Subtropical/Tropical Dry",
    "Subtropical/Tropical Seasonally Wet/Flooded",
    "Subtropical/Tropical High Altitude",
    # Wetlands (inland) -- 18 real subcategories (5.1-5.18); a fabricated
    # 19th entry ("Ephemeral Saline/Brackish/Alkaline Lakes") that does not
    # exist in the real scheme has been removed, and the real 5.18 ("Karst
    # and Other Subterranean Inland Aquatic Systems") restored in place of
    # a fabricated "Rocky Freshwater Rivers (rapids, falls)".
    "Permanent Rivers/Streams/Creeks",
    "Seasonal/Intermittent Rivers/Streams/Creeks",
    "Shrub Dominated Wetlands",
    "Bogs, Marshes, Swamps, Fens, Peatlands",
    "Permanent Freshwater Lakes (>8ha)",
    "Seasonal/Intermittent Freshwater Lakes (>8ha)",
    "Permanent Freshwater Marshes/Pools (<8ha)",
    "Seasonal/Intermittent Freshwater Marshes/Pools (<8ha)",
    "Freshwater Springs and Oases",
    "Tundra Wetlands",
    "Alpine Wetlands",
    "Geothermal Wetlands",
    "Permanent Inland Deltas",
    "Permanent Saline/Brackish/Alkaline Lakes",
    "Seasonal/Intermittent Saline/Brackish/Alkaline Lakes",
    "Permanent Saline/Brackish/Alkaline Marshes",
    "Seasonal/Intermittent Saline/Brackish/Alkaline Marshes",
    "Karst and Other Subterranean Inland Aquatic Systems",
    # Rocky Areas (inland) -- L1-only in the real scheme (no numbered L2
    # subcategories; the real document lists "inland cliffs, mountain
    # peaks, talus, feldmark" only as prose examples). The two fabricated
    # L2 rows previously here ("Inland Cliffs and Outcrops", "Scree and
    # Talus") did not exist in the real scheme and have been removed.
    NA_character_,
    # Caves
    "Dry Caves", "Other Dry Subterranean Habitats",
    # Desert
    "Hot", "Temperate", "Cold",
    # Marine Neritic -- NOTE: this entire block was previously scrambled
    # relative to the real 9.1-9.10 codes (verified directly against the
    # IUCN source document), with several entries fabricated outright
    # ("Subtidal Cave and Overhangs", "Pelagic (Supercolumnar)",
    # "Seamounts and Knolls" -- Seamount is actually real code 11.5, under
    # Marine Deep Ocean Floor, not Marine Neritic). Rebuilt in the real
    # 9.1-9.10 order.
    "Pelagic",
    "Subtidal Rock and Rocky Reefs",
    "Subtidal Loose Rock/Pebble/Gravel",
    "Subtidal Sandy",
    "Subtidal Sandy-Mud",
    "Subtidal Muddy",
    "Macroalgal/Kelp",
    "Coral Reef",
    "Seagrass (submerged)",
    "Estuaries",
    # Marine Oceanic
    "Epipelagic (0-200m)", "Mesopelagic (200-1000m)",
    "Bathypelagic (1000-4000m)", "Abyssopelagic (4000-6000m)",
    # Marine Deep Ocean Floor -- real 11.3 is "Abyssal Mountain/Hills", not
    # "Seamounts and Knolls (bathyal)"; real 11.4 ("Hadal/Deep Sea Trench")
    # starts at >6000m, not >4000m; "Seamount" is its own real code, 11.5,
    # previously missing entirely.
    "Continental Slope/Bathyal Zone (200-4000m)",
    "Abyssal Plain",
    "Abyssal Mountain/Hills",
    "Hadal/Deep Sea Trench (>6000m)",
    "Seamount",
    "Deep Sea Vents (Rifts/Seeps)",
    # Marine Intertidal -- real 12.4 is "Mud Shoreline and Intertidal Mud
    # Flats"; "Salt Flats" is not part of this real category.
    "Rocky Shoreline",
    "Sandy Shoreline and Beaches",
    "Shingle and Pebble Shoreline",
    "Mud Shoreline and Intertidal Mud Flats",
    "Salt Marshes (Emergent Grasses)",
    "Tidepools",
    "Mangrove Submerged Roots",
    # Marine Coastal/Supratidal
    "Sea Cliffs and Rocky Offshore Islands",
    "Coastal Caves/Karst",
    "Coastal Sand Dunes",
    "Coastal Brackish/Saline Lagoons",
    "Coastal Freshwater Lakes",
    # Artificial - Terrestrial -- real 14.6 keeps its "Subtropical/
    # Tropical" qualifier (unlike the L1-redundant suffixes stripped
    # elsewhere in this table, this qualifier is substantive, not
    # redundant with the "Artificial - Terrestrial" L1 name).
    "Arable Land", "Pastureland", "Plantations",
    "Rural Gardens", "Urban Areas",
    "Subtropical/Tropical Heavily Degraded Former Forest",
    # Artificial - Aquatic -- real 15.10-15.12 were previously fabricated
    # ("Marine and Freshwater (flooded mines)", "Marine - Littoral (Tidal)
    # Areas", "Marinas, Harbours, Jetties"); real 15.13 ("Mari/Brackish-
    # culture Ponds") was missing entirely. Rebuilt to match the real
    # 15.1-15.13 codes.
    "Water Storage Areas (>8ha)", "Ponds (<8ha)",
    "Aquaculture Ponds", "Salt Exploitation Sites",
    "Excavations (open)", "Wastewater Treatment Areas",
    "Irrigated Land", "Seasonally Flooded Agricultural Land",
    "Canals and Drainage Channels",
    "Karst and Other Subterranean Hydrological Systems",
    "Marine Anthropogenic Structures",
    "Mariculture Cages",
    "Mari/Brackish-culture Ponds",
    # Introduced Vegetation -- L1-only in the real scheme ("No type
    # specified"). The two fabricated L2 rows previously here ("Planted
    # Forest (monocultures)", "Other Managed/Introduced Vegetation") did
    # not exist in the real scheme and have been removed.
    NA_character_,
    # Other -- L1-only in the real scheme; the fabricated "17.0"/"Other"
    # L2 pseudo-row has been removed.
    NA_character_,
    # Unknown -- L1-only in the real scheme; the fabricated "18.0"/
    # "Unknown" L2 pseudo-row has been removed.
    NA_character_
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# build_habitat_prompt() -- returns a habitat_prompt S3 object
# ==============================================================================

#' Build a Habitat Assignment Prompt
#'
#' Creates a \code{habitat_prompt} object containing one or more LLM prompt
#' strings for habitat assignment. This is always Step 1 of the habitat
#' assignment pipeline, regardless of which submission path is used in Step 2.
#'
#' The LLM is asked to distribute habitat affinity as \strong{weights} across
#' all habitats in the scheme (summing to 1.0 per species), rather than
#' picking a single habitat. This allows habitat generalists to contribute
#' partial signal to multiple habitats at a sampling point. A special
#' \code{Other_weight} column captures species whose ecology does not fit any
#' listed habitat; these are flagged by \code{habitat_best_guess} for scheme
#' review.
#'
#' @param taxon_list Character vector of scientific names.
#' @param extra_covariates Character vector of additional binary (0/1) covariate
#'   names to request from the LLM alongside habitat weights. Default
#'   \code{character(0)} (no extra covariates). Provide a character vector
#'   (e.g. \code{c("Invasive", "Migratory")}) only when you intend to use
#'   the trait information downstream; extra covariates add tokens and output
#'   columns that are ignored by the rest of the habitat pipeline.
#' @param habitat_scheme A dataframe defining the habitat classification to use,
#'   the string \code{"IUCN_L1"}, or \code{NULL}.
#'   \code{NULL} (default) uses a simple three-category scheme:
#'   Marine, Freshwater, Terrestrial. This is always a valid starting point
#'   and is always interpretable in a model.
#'   \code{"IUCN_L1"} uses the 18 IUCN Level 1 group names as a
#'   single-level scheme. Pass a dataframe for a custom scheme (must contain
#'   \code{l1_name}; optional: \code{l2_name}, \code{l2_code}, \code{realm}).
#'   To generate a scheme automatically from the taxon list, use
#'   \code{\link{build_scheme_prompt}} + \code{\link{parse_scheme_response}}
#'   first, then pass the result here.
#'   See \code{\link{example_habitat_scheme}} for a dataframe template.
#' @param chunk_size Integer. Maximum taxa per prompt chunk. Default 60.
#'   Larger lists are split into multiple chunks automatically. Reduce if
#'   your LLM has a small context window; increase cautiously for APIs with
#'   large windows.
#' @param geographic_context Optional character string describing the geographic
#'   region where these species were observed (e.g. \code{"Southern California"},
#'   \code{"Chesapeake Bay watershed"}). When non-NULL, the prompt includes a
#'   geographic context block and requests an additional \code{ecoregion_best_guess}
#'   column from the LLM. Default \code{NULL} (no geographic context).
#'
#' @return An object of class \code{c("habitat_prompt", "llm_prompt")}, which
#'   is a named list:
#'   \describe{
#'     \item{prompts}{List of character strings, one per chunk.}
#'     \item{taxa}{Character vector of deduplicated, trimmed taxon names.}
#'     \item{chunks}{List of character vectors, taxa per chunk.}
#'     \item{scheme}{The validated habitat scheme dataframe.}
#'     \item{habitat_cols}{Character vector of habitat column names the LLM
#'       will produce (the scheme's working habitat names, in order). Used by
#'       \code{\link{parse_hierarchical_habitat_response}} to identify weight
#'       columns.}
#'     \item{extra_covariates}{The covariate names used.}
#'     \item{geographic_context}{The geographic context string, or \code{NULL}.}
#'     \item{chunk_size}{The chunk size used.}
#'     \item{n_chunks}{Integer. Number of chunks.}
#'   }
#'   Print the object for a summary. Pass to \code{\link[TaxaTools]{prompt_api}}
#'   (Path 1/2) or \code{\link[TaxaTools]{prompt_manual}} (Path 3).
#'
#' @details
#' \strong{Output shape from the LLM:} The LLM returns a CSV with one row per
#' species. Each listed habitat is a column containing a numeric weight
#' (0.0-1.0). All habitat weights plus \code{Other_weight} sum to 1.0.
#' \code{habitat_best_guess} is a free-text column populated only when
#' \code{Other_weight > 0}; it records the LLM's best description of the
#' species' actual habitat for scheme review.
#'
#' \strong{Pipeline:}
#' \preformatted{
#' prompt   <- build_habitat_prompt(taxa_in_data)
#' raw_text <- TaxaTools::prompt_api(prompt)      # Path 1
#' # OR
#' TaxaTools::prompt_manual(prompt)               # Path 3
#' raw_text <- TaxaTools::read_llm_response("habitat_response_1.txt")
#'
#' hab_tbl  <- parse_hierarchical_habitat_response(raw_text, taxa_in_data,
#'                                                 habitat_scheme = prompt)
#' }
#'
#' \strong{Chunking:} For lists longer than \code{chunk_size}, the taxon list
#' is split into chunks and one prompt string is built per chunk. Each chunk
#' is self-contained. Chunks must be submitted and parsed independently; do
#' not concatenate prompts before submitting.
#'
#' @seealso \code{\link[TaxaTools]{prompt_api}}, \code{\link[TaxaTools]{prompt_manual}},
#'   \code{\link{parse_hierarchical_habitat_response}}
#'
#' @export
#'
#' @examples
#' taxa <- c("Gadus morhua", "Sebastes mystinus", "Oncorhynchus mykiss")
#'
#' # Default 3-category scheme (Marine/Freshwater/Terrestrial)
#' prompt <- build_habitat_prompt(taxa)
#' print(prompt)
#'
#' # A custom two-level scheme (see example_habitat_scheme for the required
#' # l1_name/l2_name/l2_code/realm shape)
#' custom_prompt <- build_habitat_prompt(taxa, habitat_scheme = example_habitat_scheme)
#' print(custom_prompt)
#'
#' \dontrun{
#' # View the raw prompt text for the first chunk
#' cat(prompt$prompts[[1]])
#' }
build_habitat_prompt <- function(
  taxon_list,
  extra_covariates = character(0),
  chunk_size = 60L,
  habitat_scheme = NULL,
  geographic_context = NULL
) {
  if (!is.character(taxon_list) || length(taxon_list) == 0) {
    stop("build_habitat_prompt: 'taxon_list' must be a non-empty character vector.")
  }
  if (!is.character(extra_covariates)) {
    stop("build_habitat_prompt: 'extra_covariates' must be a character vector.")
  }
  if (!is.numeric(chunk_size) || chunk_size < 1) {
    stop("build_habitat_prompt: 'chunk_size' must be a positive integer.")
  }
  if (!is.null(geographic_context)) {
    if (!is.character(geographic_context) || length(geographic_context) != 1L ||
      is.na(geographic_context) || !nzchar(trimws(geographic_context))) {
      stop("build_habitat_prompt: 'geographic_context' must be NULL or a non-empty string.")
    }
  }

  # Handle habitat_scheme shortcuts and NULL default
  if (is.null(habitat_scheme)) {
    # Default: three broad realm categories -- always valid, always interpretable.
    # For finer resolution use build_scheme_prompt() or supply a custom scheme.
    habitat_scheme <- data.frame(
      l1_name = c("Marine", "Freshwater", "Terrestrial"),
      l2_name = NA_character_,
      l2_code = NA_character_,
      realm = c("marine", "freshwater", "terrestrial"),
      stringsAsFactors = FALSE
    )
  } else if (identical(habitat_scheme, "IUCN_L1")) {
    # String shortcut: 18 IUCN Level 1 group names as a single-level scheme.
    habitat_scheme <- data.frame(
      l1_name = unique(.iucn_habitat_lookup$l1_name),
      l2_name = NA_character_,
      l2_code = NA_character_,
      realm = .l1_to_realm(unique(.iucn_habitat_lookup$l1_name)),
      stringsAsFactors = FALSE
    )
  }

  # Validate and normalise the habitat_scheme dataframe right after the
  # NULL/"IUCN_L1" shortcuts are resolved, and before any taxon_list work --
  # a malformed custom scheme (missing l1_name, bad realm values, duplicate
  # l2_name) should fail fast rather than after paying for taxon_list
  # deduplication/messaging first.
  scheme <- .validate_habitat_scheme(habitat_scheme)

  taxon_list <- trimws(taxon_list)
  taxon_list <- taxon_list[nzchar(taxon_list)]
  n_input <- length(taxon_list)
  taxon_list <- unique(taxon_list)
  n_deduped <- n_input - length(taxon_list)
  if (n_deduped > 0L) {
    message(sprintf(
      "build_habitat_prompt: removed %d duplicate taxon name(s) (%d unique of %d input).",
      n_deduped, length(taxon_list), n_input
    ))
  }
  chunk_size <- as.integer(chunk_size)

  # Derive the ordered vector of habitat column names the LLM will produce.
  # Mixed schemes (from build_iucn_scheme with both L1 and L2 rows):
  #   L2 names for rows where l2_name is non-NA, PLUS L1 names for rows where
  #   l2_name is NA (the L1-only fallback rows). This preserves the ability
  #   for the LLM to assign at L1 when it cannot distinguish L2 subcategories.
  # Two-level custom schemes: l2_name only (all rows have an l2_name).
  # Single-level schemes: l1_name only (all l2_name are NA).
  has_l1_only_rows <- any(is.na(scheme$l2_name))
  has_l2_rows <- any(!is.na(scheme$l2_name) & nzchar(trimws(scheme$l2_name)))

  if (has_l2_rows && has_l1_only_rows) {
    # Mixed scheme: L2 names + L1 fallback names
    l2_cols <- scheme$l2_name[!is.na(scheme$l2_name) & nzchar(trimws(scheme$l2_name))]
    l1_cols <- scheme$l1_name[is.na(scheme$l2_name)]
    habitat_cols <- unique(c(l2_cols, l1_cols))
  } else if (has_l2_rows) {
    # Pure two-level custom scheme
    habitat_cols <- unique(scheme$l2_name[!is.na(scheme$l2_name) &
      nzchar(trimws(scheme$l2_name))])
  } else {
    # Single-level scheme (all l2_name NA)
    habitat_cols <- unique(scheme$l1_name)
  }

  chunks <- split(taxon_list, ceiling(seq_along(taxon_list) / chunk_size))
  n_chunks <- length(chunks)

  prompts <- lapply(chunks, function(chunk_taxa) {
    .build_single_prompt(
      chunk_taxa, extra_covariates, scheme, habitat_cols,
      geographic_context
    )
  })

  structure(
    list(
      prompts            = prompts,
      taxa               = taxon_list,
      chunks             = chunks,
      scheme             = scheme,
      habitat_cols       = habitat_cols,
      extra_covariates   = extra_covariates,
      geographic_context = geographic_context,
      chunk_size         = chunk_size,
      n_chunks           = n_chunks
    ),
    class = c("habitat_prompt", "llm_prompt")
  )
}


#' Print a habitat_prompt Object
#'
#' @param x A \code{habitat_prompt} object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export

print.habitat_prompt <- function(x, ...) {
  cat("<habitat_prompt>\n")
  cat(sprintf("  Taxa:        %d species\n", length(x$taxa)))
  if (x$n_chunks == 1L) {
    cat(sprintf("  Chunks:      1 (chunk_size = %d)\n", x$chunk_size))
  } else {
    chunk_sizes <- vapply(x$chunks, length, integer(1))
    cat(sprintf(
      "  Chunks:      %d (chunk_size = %d, sizes: %s)\n",
      x$n_chunks, x$chunk_size,
      paste(chunk_sizes, collapse = ", ")
    ))
  }
  cat(sprintf("  Habitats:    %d columns (+ Other_weight)\n", length(x$habitat_cols)))
  if (!is.null(x$geographic_context)) {
    cat(sprintf("  Geographic:  %s\n", x$geographic_context))
  }
  if (length(x$extra_covariates) > 0L) {
    cat(sprintf("  Covariates:  %s\n", paste(x$extra_covariates, collapse = ", ")))
  } else {
    cat("  Covariates:  (none)\n")
  }
  cat(sprintf(
    "  Prompt tokens (approx): ~%d per chunk\n",
    nchar(x$prompts[[1]]) %/% 4L
  ))
  invisible(x)
}


# ==============================================================================
# Internal: build one prompt string for a single chunk of taxa
# ==============================================================================

#' Build one prompt string for a chunk of taxa
#' @noRd
.build_single_prompt <- function(taxon_chunk, extra_covariates, scheme, habitat_cols,
                                 geographic_context = NULL) {
  species_block <- paste(paste0('"', trimws(taxon_chunk), '"'), collapse = ", ")

  # ---- Shared weight-column instructions -------------------------------------
  # These appear in both IUCN and custom branches.
  weight_rules <- paste0(
    "HABITAT WEIGHT RULES:\n",
    "1. For each species, assign a numeric weight (0.0 to 1.0) to every ",
    "habitat column listed below. Weights across all habitat columns ",
    "PLUS Other_weight must sum to exactly 1.0 for each species.\n",
    "2. A weight of 0.0 means the species does not use that habitat. ",
    "A weight of 1.0 means it is exclusively found there.\n",
    "3. Distribute weight across multiple habitats for genuine habitat ",
    "generalists (e.g. an anadromous fish that uses ocean AND rivers ",
    "might receive 0.5 to each). Most specialists will have one column ",
    "near 1.0 and the rest near 0.0.\n",
    "4. If the species does not fit ANY of the listed habitats at all, ",
    "set Other_weight = 1.0, all other habitat columns = 0.0, and fill ",
    "habitat_best_guess with a short free-text description of its actual ",
    "primary habitat (e.g. 'alpine meadow', 'deep-sea hydrothermal vent').\n",
    "5. If the species partially fits the listed habitats but also uses ",
    "unlisted ones, split weight appropriately between listed columns and ",
    "Other_weight, and fill habitat_best_guess for the unlisted portion.\n",
    "6. Leave habitat_best_guess empty (blank cell) when Other_weight = 0.\n",
    "7. If a species is unknown to you, use your best ecological judgement ",
    "based on genus or family.\n",
    "8. OUTPUT FORMAT: Return ONLY a raw CSV block. ",
    "Do not use Markdown code fences. ",
    "Do not include any preamble, explanation, or closing text. ",
    "The first line must be the header row. ",
    "Use 2 decimal places for all weights. ",
    if (!is.null(geographic_context)) {
      paste0(
        "If habitat_best_guess or ecoregion_best_guess contains a comma, "
      )
    } else {
      "If habitat_best_guess contains a comma, "
    },
    "wrap the ENTIRE field value in double quotes, standard CSV convention ",
    "(e.g. \"tidal marsh, brackish water\") -- otherwise the comma will be ",
    "misread as a column separator.\n",
    if (!is.null(geographic_context)) {
      paste0(
        "9. ecoregion_best_guess: Name the most specific recognized ecoregion ",
        "where this species is most likely found within the stated geographic ",
        "context (e.g. 'Southern California Bight', 'Great Barrier Reef', ",
        "'Chesapeake Bay'). Use the same ecoregion for co-occurring species. ",
        "Leave blank if the species is not associated with the geographic context.\n"
      )
    } else {
      ""
    },
    "\n"
  )

  # ---- Extra covariates (optional) ------------------------------------------
  covariate_section <- if (length(extra_covariates) > 0L) {
    paste0(
      "ADDITIONAL BINARY COVARIATES (0 or 1 for each species):\n",
      paste(extra_covariates, collapse = ", "), "\n",
      "Set each to 1 if the trait applies to the adult stage, 0 if it does not.\n\n"
    )
  } else {
    ""
  }

  # ---- Build required columns string ----------------------------------------
  # taxon_name | [habitat cols...] | Other_weight | habitat_best_guess | [extra covariates]
  required_cols <- paste(
    c(
      "taxon_name", habitat_cols, "Other_weight", "habitat_best_guess",
      if (!is.null(geographic_context)) "ecoregion_best_guess",
      extra_covariates
    ),
    collapse = ", "
  )

  # ---- Custom / default scheme -----------------------------------------------
  # Handles: 3-category default, IUCN_L1, user custom (single or two-level),
  # mixed L1+L2 from build_iucn_scheme(), and auto-generated from build_scheme_prompt.
  two_level <- .is_two_level(scheme)

  if (two_level) {
    # A mixed-scale scheme (e.g. from build_iucn_scheme() with both L1
    # fallback rows and L2 rows present) has l2_name = NA on its L1-only
    # rows -- display_name falls back to l1_name for those specific rows
    # so the prompt shows the real group name instead of literal "NA"
    # (confirmed as a real, reproducible bug: build_iucn_scheme(realm =
    # "terrestrial", l2 = "Temperate") followed by build_habitat_prompt()
    # previously sent "NA  [Forest]", "NA  [Savanna]", etc. to the LLM for
    # every L1 fallback row).
    display_name <- ifelse(is.na(scheme$l2_name), scheme$l1_name, scheme$l2_name)
    hab_block <- paste(
      sprintf(
        "  %-20s %s  [%s]",
        ifelse(is.na(scheme$l2_code), "", scheme$l2_code),
        display_name,
        scheme$l1_name
      ),
      collapse = "\n"
    )
    class_header <- "HABITAT CLASSES:\n(format: code  name  [group])\n"
    col_note <- paste0(
      "The column name for each habitat is its exact name as listed above ",
      "(e.g. '", habitat_cols[1], "').\n\n"
    )
  } else {
    hab_block <- paste(sprintf("  %s", scheme$l1_name), collapse = "\n")
    class_header <- "HABITAT CLASSES:\n"
    col_note <- paste0(
      "The column name for each habitat is its exact name as listed above ",
      "(e.g. '", habitat_cols[1], "').\n\n"
    )
  }

  paste0(
    "Act as an expert ecologist and taxonomist.\n\n",
    "I will provide a list of species and a habitat classification. ",
    "For each species, distribute habitat affinity as numeric weights across ",
    "the habitat columns listed below. Weights capture habitat breadth: a ",
    "specialist gets 1.0 in one column; a generalist splits weight across ",
    "several.\n\n",
    class_header,
    hab_block, "\n\n",
    col_note,
    covariate_section,
    weight_rules,
    "REQUIRED COLUMNS (in this order):\n",
    required_cols, "\n\n",
    if (!is.null(geographic_context)) {
      paste0(
        "GEOGRAPHIC CONTEXT:\n",
        "These species were observed in or near: ", geographic_context, "\n",
        "Use this to resolve habitat ambiguities for widely-distributed taxa.\n\n"
      )
    } else {
      ""
    },
    "SPECIES LIST:\n",
    species_block
  )
}


# ==============================================================================
# .validate_habitat_scheme() -- internal helper
# ==============================================================================

#' Validate and normalise a habitat scheme dataframe
#'
#' Accepts a user-supplied scheme or NULL (returns .iucn_habitat_lookup).
#' Ensures required column exists; pads optional columns with NA if absent.
#' @noRd
.validate_habitat_scheme <- function(scheme) {
  if (is.null(scheme)) {
    stop(
      ".validate_habitat_scheme: received NULL scheme. ",
      "This should have been converted to the default 3-category scheme ",
      "before reaching this function. Please report this as a bug.",
      call. = FALSE
    )
  }

  if (!is.data.frame(scheme)) {
    stop("habitat_scheme must be a dataframe with at least a 'l1_name' column.")
  }
  if (!"l1_name" %in% names(scheme)) {
    stop("habitat_scheme must contain a 'l1_name' column (the grouping level).")
  }
  if (any(is.na(scheme$l1_name) | !nzchar(trimws(scheme$l1_name)))) {
    stop("habitat_scheme: 'l1_name' must not contain NA or blank values.")
  }

  # Pad optional columns with NA if absent
  if (!"l2_code" %in% names(scheme)) scheme$l2_code <- NA_character_
  if (!"l2_name" %in% names(scheme)) scheme$l2_name <- NA_character_
  if (!"realm" %in% names(scheme)) scheme$realm <- NA_character_

  # Validate realm values where supplied
  valid_realms <- c("marine", "freshwater", "terrestrial", NA)
  bad_realms <- !scheme$realm %in% valid_realms
  if (any(bad_realms)) {
    stop(sprintf(
      "habitat_scheme: 'realm' column contains invalid values: %s. Use 'marine', 'freshwater', or 'terrestrial'.",
      paste(unique(scheme$realm[bad_realms]), collapse = ", ")
    ))
  }

  # Duplicate l2_name check
  dups <- scheme$l2_name[!is.na(scheme$l2_name) & duplicated(scheme$l2_name)]
  if (length(dups) > 0L) {
    stop(
      "habitat_scheme: duplicate l2_name values found: ",
      paste(unique(dups), collapse = ", "),
      call. = FALSE
    )
  }

  scheme[, c("l1_name", "l2_code", "l2_name", "realm")]
}


#' Is a normalised scheme two-level (has any non-NA l2_name)?
#' @noRd
.is_two_level <- function(scheme) {
  any(!is.na(scheme$l2_name) & nzchar(trimws(scheme$l2_name)))
}


#' Is a scheme derived from the IUCN lookup?
#' Checked by presence of an l2_code column populated with IUCN-style
#' numeric codes ("9.1", "1.3", etc.).
#'
#' Previously also checked \code{identical(scheme, .iucn_habitat_lookup)}
#' and required an \code{l1_code} column. Both were dead in practice: every
#' scheme reaching this function has already passed through
#' \code{.validate_habitat_scheme()}, which subsets to
#' \code{c("l1_name", "l2_code", "l2_name", "realm")} and never preserves
#' \code{l1_code} -- so \code{identical()} against the raw (differently-
#' shaped) \code{.iucn_habitat_lookup} could never succeed, and the
#' \code{l1_code} membership check could never be TRUE either. Confirmed via
#' \code{build_iucn_scheme()}'s own \code{@return} (only
#' \code{l1_name}/\code{l2_name}/\code{l2_code}/\code{realm}) and a grep of
#' every call site. The \code{l2_code} pattern check below is the only part
#' that was ever actually reachable.
#' @noRd
.is_iucn_scheme <- function(scheme) {
  all(c("l2_code", "l1_name", "l2_name") %in% names(scheme)) &&
    any(grepl("^[0-9]+\\.[0-9]+$", scheme$l2_code, perl = TRUE))
}


# ==============================================================================
# example_habitat_scheme -- exported template for custom habitat classifications
# ==============================================================================

#' Example Custom Habitat Scheme
#'
#' A small example \code{habitat_scheme} dataframe illustrating the structure
#' required by \code{\link{build_habitat_prompt}},
#' \code{\link{parse_hierarchical_habitat_response}}, and
#' \code{\link{flag_habitat_inconsistencies}} when using a custom (non-IUCN)
#' habitat classification.
#'
#' @format A dataframe with 10 rows and 4 columns:
#' \describe{
#'   \item{l1_name}{Grouping level (L1). Sparse L2 categories are collapsed
#'     to this label during modelling. Must not be \code{NA}.}
#'   \item{l2_name}{Working category (L2). The label assigned to each species
#'     by the LLM. \code{NA} if the scheme is single-level.}
#'   \item{l2_code}{Short code for each L2 category. May be \code{NA} if
#'     codes are not meaningful in your classification.}
#'   \item{realm}{Ecological realm: \code{"marine"}, \code{"freshwater"}, or
#'     \code{"terrestrial"}. Used by
#'     \code{\link{flag_habitat_inconsistencies}} to check whether occurrence
#'     points are in the right environment. \code{NA} triggers name-pattern
#'     fallback.}
#' }
#'
#' @details
#' Copy and edit this object as a starting point for your own scheme:
#' \preformatted{
#' my_scheme <- example_habitat_scheme
#'
#' # Use with the full pipeline:
#' prompt   <- build_habitat_prompt(taxa, habitat_scheme = my_scheme)
#' raw_text <- TaxaTools::prompt_api(prompt)
#' hab_tbl  <- parse_hierarchical_habitat_response(raw_text, taxa,
#'                                                 habitat_scheme = prompt)
#' flagged  <- flag_habitat_inconsistencies(occ, habitat_scheme = prompt)
#' }
#'
#' For a single-level scheme (no L2 distinction), set \code{l2_name} and
#' \code{l2_code} to \code{NA} for all rows. The LLM will then assign
#' \code{l1_name} values directly.
#'
#' @seealso \code{\link{build_habitat_prompt}},
#'   \code{\link{parse_hierarchical_habitat_response}},
#'   \code{\link{flag_habitat_inconsistencies}}
#'
#' @examples
#' head(example_habitat_scheme)
#'
#' @export

example_habitat_scheme <- data.frame(
  l1_name = c(
    "Kelp Forest",   "Kelp Forest",
    "Rocky Reef",    "Rocky Reef",
    "Soft Bottom",   "Soft Bottom",
    "Pelagic",       "Pelagic",
    "Estuarine",     "Estuarine"
  ),
  l2_name = c(
    "Shallow Kelp Forest (<10m)", "Deep Kelp Forest (>10m)",
    "Rocky Subtidal",             "Rocky Intertidal",
    "Sandy Subtidal",             "Muddy Subtidal",
    "Coastal Pelagic",            "Offshore Pelagic",
    "Estuarine Open Water",       "Estuarine Mudflat"
  ),
  l2_code = c(
    "KF1", "KF2",
    "RR1", "RR2",
    "SB1", "SB2",
    "PE1", "PE2",
    "ES1", "ES2"
  ),
  realm = rep("marine", 10),
  stringsAsFactors = FALSE
)


#' Map IUCN L1 group names to realm values for flag_habitat_inconsistencies
#'
#' Only "marine", "freshwater", and "terrestrial" are valid values for the
#' \code{realm} column (see \code{.validate_habitat_scheme()}'s
#' \code{valid_realms}) -- there is no "artificial" realm value, since
#' Artificial - Aquatic genuinely spans both marine (e.g. Mariculture Cages)
#' and freshwater (e.g. Ponds) use cases and cannot be resolved from the L1
#' group name alone. That one group -- along with "Other" and "Unknown",
#' which have no real-world realm at all -- is deliberately left \code{NA};
#' \code{flag_habitat_inconsistencies()}'s own \code{.realm()} name-pattern
#' fallback already defaults anything not matched to "terrestrial", so this
#' NA does not silently misclassify anything downstream.
#' @noRd
.l1_to_realm <- function(l1_names) {
  marine_groups <- c(
    "Marine Neritic", "Marine Oceanic",
    "Marine Deep Ocean Floor", "Marine Intertidal",
    "Marine Coastal/Supratidal"
  )
  freshwater_groups <- c("Wetlands (inland)")
  terrestrial_groups <- c(
    "Forest", "Savanna", "Shrubland", "Grassland",
    "Rocky Areas (inland)",
    "Caves and Subterranean Habitats", "Desert",
    "Introduced Vegetation", "Artificial - Terrestrial"
  )
  ifelse(l1_names %in% marine_groups, "marine",
    ifelse(l1_names %in% freshwater_groups, "freshwater",
      ifelse(l1_names %in% terrestrial_groups, "terrestrial",
        NA_character_
      )
    )
  )
}


# ==============================================================================
# build_iucn_scheme() -- construct a habitat_scheme from the IUCN classification
# ==============================================================================

#' Build a Habitat Scheme from the IUCN Red List Classification
#'
#' Constructs a \code{habitat_scheme} dataframe by subsetting the IUCN Red List
#' Habitat Classification v3.1 to the realms, Level 1 groups, and Level 2
#' subcategories you specify. The result can be passed directly to
#' \code{\link{build_habitat_prompt}} as \code{habitat_scheme}.
#'
#' Call with no arguments (or just \code{realm}) to discover what is available
#' before committing to a specific selection. The printed output lists the
#' available L1 groups and L2 subcategories at each level of filtering.
#'
#' @param realm Character or \code{NULL}. Filter to one ecological realm:
#'   \code{"marine"}, \code{"freshwater"}, \code{"terrestrial"},
#'   \code{"artificial"}, or \code{NULL} (all realms, default). Realm
#'   groupings:
#'   \itemize{
#'     \item \code{"marine"}: Marine Neritic, Marine Oceanic, Marine Deep
#'       Ocean Floor, Marine Intertidal, Marine Coastal/Supratidal
#'     \item \code{"freshwater"}: Wetlands (inland)
#'     \item \code{"terrestrial"}: Forest, Savanna, Shrubland, Grassland,
#'       Rocky Areas (inland), Caves and Subterranean Habitats, Desert,
#'       Introduced Vegetation
#'     \item \code{"artificial"}: Artificial - Terrestrial, Artificial - Aquatic
#'   }
#'   \code{"Other"} and \code{"Unknown"} are excluded from all realm filters
#'   and must be requested explicitly via \code{l1}.
#' @param l1 Character, \code{"all"}, or \code{"none"}. Which Level 1 groups
#'   to include in the scheme. \code{"all"} (default) includes all L1 groups
#'   in the selected realm as single-level categories. \code{"none"} excludes
#'   all L1 groups (only L2 subcategories will be present; requires \code{l2}
#'   to be non-\code{"none"}). A character vector of L1 group names includes
#'   only those groups as fallback L1 columns alongside any L2 subcategories
#'   requested. Names are validated against the filtered lookup and a helpful
#'   error is given for unrecognised values.
#' @param l2 Character, \code{"all"}, or \code{"none"}. Which Level 2
#'   subcategories to include. \code{"none"} (default) produces a single-level
#'   scheme using only L1 group names. \code{"all"} adds all L2 subcategories
#'   under the selected L1 groups. A character vector of specific L2 names
#'   adds only those subcategories; their L1 parent groups are automatically
#'   added as fallback columns unless \code{l1 = "none"}. Names are validated
#'   and an error lists the correct L1 parent for any unrecognised value.
#'
#' @return A \code{habitat_scheme} data.frame with columns \code{l1_name},
#'   \code{l2_name}, \code{l2_code}, and \code{realm}, ready for
#'   \code{\link{build_habitat_prompt}}. Rows with \code{l2_name = NA} are
#'   L1-only entries (single-level fallback); rows with non-NA \code{l2_name}
#'   are L2 entries. Print the result to inspect the scheme before use.
#'
#' @details
#' \strong{Iterative discovery:} Call with broad filters first to see what is
#' available, then narrow:
#' \preformatted{
#' build_iucn_scheme()                           # all 16 L1 groups (Other/Unknown excluded by default)
#' build_iucn_scheme(realm = "marine")           # 5 marine L1 groups
#' build_iucn_scheme(realm = "marine", l2 = "all")  # marine L1 + all 32 L2
#' build_iucn_scheme(realm = "marine",
#'   l2 = c("Subtidal Rock and Rocky Reefs", "Estuaries",
#'           "Macroalgal/Kelp"))                 # specific marine L2 + parent L1
#' }
#'
#' \strong{Scale mixing:} When both L1 and L2 entries are present, the scheme
#' is mixed-scale. This is valid as long as no two species in your dataset
#' share an L1 group where one is assigned at L1 and another at L2 (which
#' would create nested predictors in the model). For focused single-realm
#' datasets, use \code{l1 = "none", l2 = "all"} to get a flat L2-only scheme,
#' or \code{l2 = "none"} for a flat L1-only scheme.
#'
#' \strong{A common surprise:} \code{l1} defaults to \code{"all"}, so
#' supplying \code{l2} \emph{without} also setting \code{l1 = "none"}
#' returns BOTH an L1-only fallback row for every L1 group in the realm
#' (\code{l2_name = NA}) AND the specific L2 rows you asked for -- e.g.
#' \code{build_iucn_scheme(realm = "terrestrial", l2 = "Temperate")} returns
#' all 8 terrestrial L1 groups as single-level rows PLUS 4 disambiguated
#' \code{"Temperate (...)"} L2 rows (Forest/Shrubland/Grassland/Desert all
#' have a "Temperate" subcategory). This is the documented mixed-scale
#' behaviour above, not a bug -- but if you only want the L2 rows, pass
#' \code{l1 = "none"} explicitly.
#'
#' \strong{Duplicate L2 names:} Some L2 names (e.g. "Boreal", "Temperate")
#' appear under multiple L1 groups. When these are selected, the function
#' disambiguates by appending the L1 parent in parentheses:
#' e.g. "Boreal (Forest)" and "Boreal (Shrubland)".
#'
#' @seealso \code{\link{build_habitat_prompt}}, \code{\link{build_scheme_prompt}}
#'
#' @export
#'
#' @examples
#' # Discover what is available
#' build_iucn_scheme()
#' build_iucn_scheme(realm = "marine")
#' build_iucn_scheme(realm = "freshwater", l2 = "all")
#'
#' # Build a specific marine scheme with selected L2 subcategories
#' scheme <- build_iucn_scheme(
#'   realm = "marine",
#'   l2 = c(
#'     "Subtidal Rock and Rocky Reefs", "Estuaries", "Macroalgal/Kelp",
#'     "Subtidal Sandy", "Rocky Shoreline"
#'   )
#' )
#' print(scheme)
#' taxa <- c("Gadus morhua", "Oncorhynchus mykiss")
#' prompt <- build_habitat_prompt(taxa, habitat_scheme = scheme)
build_iucn_scheme <- function(realm = NULL,
                              l1 = "all",
                              l2 = "none") {
  # ---------------------------------------------------------------------------
  # Realm groupings
  # ---------------------------------------------------------------------------
  .realm_to_l1 <- list(
    marine = c(
      "Marine Neritic", "Marine Oceanic", "Marine Deep Ocean Floor",
      "Marine Intertidal", "Marine Coastal/Supratidal"
    ),
    freshwater = c("Wetlands (inland)"),
    terrestrial = c(
      "Forest", "Savanna", "Shrubland", "Grassland",
      "Rocky Areas (inland)", "Caves and Subterranean Habitats",
      "Desert", "Introduced Vegetation"
    ),
    artificial = c("Artificial - Terrestrial", "Artificial - Aquatic")
  )
  # "Other" and "Unknown" excluded from realm filters; must be requested via l1

  valid_realms <- names(.realm_to_l1)

  # ---------------------------------------------------------------------------
  # Input checks
  # ---------------------------------------------------------------------------
  if (!is.null(realm)) {
    if (!is.character(realm) || length(realm) != 1L ||
      !realm %in% valid_realms) {
      stop(sprintf(
        "build_iucn_scheme: 'realm' must be one of: %s, or NULL.\nGot: %s",
        paste(valid_realms, collapse = ", "),
        if (is.null(realm)) "NULL" else realm
      ))
    }
  }

  if (!is.character(l1) || length(l1) == 0L) {
    stop("build_iucn_scheme: 'l1' must be \"all\", \"none\", or a character vector of L1 names.")
  }
  if (!is.character(l2) || length(l2) == 0L) {
    stop("build_iucn_scheme: 'l2' must be \"all\", \"none\", or a character vector of L2 names.")
  }

  if (identical(l1, "none") && identical(l2, "none")) {
    stop("build_iucn_scheme: 'l1' and 'l2' cannot both be \"none\".")
  }

  # ---------------------------------------------------------------------------
  # Step 1: filter lookup to realm
  # ---------------------------------------------------------------------------
  lookup <- .iucn_habitat_lookup

  if (!is.null(realm)) {
    realm_l1 <- .realm_to_l1[[realm]]
    lookup <- lookup[lookup$l1_name %in% realm_l1, , drop = FALSE]
  } else {
    # Exclude Other/Unknown unless explicitly requested
    lookup <- lookup[!lookup$l1_name %in% c("Other", "Unknown"), , drop = FALSE]
  }

  all_l1_in_scope <- unique(lookup$l1_name)
  # Exclude NA: a handful of L1 groups (Rocky Areas (inland), Introduced
  # Vegetation, Other, Unknown) have no real L2 subcategory at all in the
  # source scheme and are represented by a single l2_name = NA row -- those
  # groups are only reachable via 'l1', never via 'l2' (NA would otherwise
  # match itself through %in%/match() and let 'l2 = "all"' silently pull in
  # duplicate L1-only rows already added by the 'l1' argument).
  all_l2_in_scope <- unique(lookup$l2_name[!is.na(lookup$l2_name)])

  # ---------------------------------------------------------------------------
  # Step 2: validate and resolve l1 argument
  # ---------------------------------------------------------------------------
  if (identical(l1, "all")) {
    selected_l1 <- all_l1_in_scope
  } else if (identical(l1, "none")) {
    selected_l1 <- character(0)
  } else {
    bad_l1 <- setdiff(l1, all_l1_in_scope)
    if (length(bad_l1) > 0L) {
      # Helpful error: show valid options in the current realm scope
      stop(sprintf(
        paste0(
          "build_iucn_scheme: unrecognised L1 name(s)%s: %s\n",
          "Available L1 groups%s:\n  %s"
        ),
        if (!is.null(realm)) sprintf(" in realm '%s'", realm) else "",
        paste(bad_l1, collapse = ", "),
        if (!is.null(realm)) sprintf(" (realm = '%s')", realm) else "",
        paste(all_l1_in_scope, collapse = "\n  ")
      ))
    }
    selected_l1 <- l1
  }

  # ---------------------------------------------------------------------------
  # Step 3: validate and resolve l2 argument
  # ---------------------------------------------------------------------------
  if (identical(l2, "none")) {
    selected_l2 <- character(0)
  } else if (identical(l2, "all")) {
    selected_l2 <- all_l2_in_scope
  } else {
    bad_l2 <- setdiff(l2, all_l2_in_scope)
    if (length(bad_l2) > 0L) {
      # Check if they exist in a different realm/l1 to give a useful hint
      all_lookup_l2 <- unique(.iucn_habitat_lookup$l2_name)
      exists_elsewhere <- intersect(bad_l2, all_lookup_l2)
      not_in_iucn <- setdiff(bad_l2, all_lookup_l2)

      msg <- sprintf(
        "build_iucn_scheme: unrecognised L2 name(s)%s: %s",
        if (!is.null(realm)) sprintf(" in realm '%s'", realm) else "",
        paste(bad_l2, collapse = ", ")
      )
      if (length(exists_elsewhere) > 0L) {
        # Find the L1 parent(s) for each misplaced name
        parents <- vapply(exists_elsewhere, function(nm) {
          rows <- .iucn_habitat_lookup[.iucn_habitat_lookup$l2_name == nm, ]
          paste(unique(rows$l1_name), collapse = " / ")
        }, character(1))
        msg <- paste0(
          msg, "\nThese exist under a different L1 group:\n",
          paste(sprintf("  '%s' -> parent: %s", exists_elsewhere, parents),
            collapse = "\n"
          )
        )
      }
      if (length(not_in_iucn) > 0L) {
        msg <- paste0(
          msg, "\nThese are not in the IUCN classification at all: ",
          paste(not_in_iucn, collapse = ", ")
        )
      }
      msg <- paste0(
        msg, "\nAvailable L2 names in current scope:\n  ",
        paste(all_l2_in_scope, collapse = "\n  ")
      )
      stop(msg)
    }
    selected_l2 <- l2

    # Auto-add L1 parents of selected L2 (unless l1 = "none")
    if (!identical(l1, "none")) {
      l2_parents <- unique(
        lookup$l1_name[lookup$l2_name %in% selected_l2]
      )
      # Add parents not already in selected_l1
      if (!identical(l1, "all")) {
        new_parents <- setdiff(l2_parents, selected_l1)
        if (length(new_parents) > 0L) {
          message(sprintf(
            "build_iucn_scheme: auto-adding L1 parent group(s) for selected L2: %s",
            paste(new_parents, collapse = ", ")
          ))
          selected_l1 <- unique(c(selected_l1, new_parents))
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Step 4: handle duplicate L2 names (disambiguate with L1 parent)
  # ---------------------------------------------------------------------------
  if (length(selected_l2) > 0L) {
    l2_rows <- lookup[lookup$l2_name %in% selected_l2, , drop = FALSE]
    dup_l2 <- l2_rows$l2_name[duplicated(l2_rows$l2_name)]
    if (length(dup_l2) > 0L) {
      message(sprintf(
        paste0(
          "build_iucn_scheme: %d L2 name(s) appear under multiple L1 groups ",
          "and have been disambiguated with '(L1 parent)': %s"
        ),
        length(unique(dup_l2)),
        paste(unique(dup_l2), collapse = ", ")
      ))
      # Rename duplicates in the lookup subset
      for (i in seq_len(nrow(l2_rows))) {
        if (l2_rows$l2_name[i] %in% dup_l2) {
          l2_rows$l2_name[i] <- sprintf(
            "%s (%s)",
            l2_rows$l2_name[i],
            l2_rows$l1_name[i]
          )
        }
      }
    }
  } else {
    l2_rows <- NULL
  }

  # ---------------------------------------------------------------------------
  # Step 5: build the scheme dataframe
  # ---------------------------------------------------------------------------
  # L1-only rows: one row per selected L1 group with l2_name = NA
  # L2 rows: from the filtered lookup (with possible disambiguation)
  # If l1 = "none", only L2 rows are included (flat L2-only scheme)

  # realm column: when the caller supplied a specific 'realm' argument, every
  # row in this scheme belongs to that realm by construction (Step 1 already
  # filtered `lookup` down to that realm's own L1 groups) -- use it directly.
  # `.l1_to_realm()` only recognises marine/freshwater L1 group names and
  # returns NA for everything else (including "terrestrial" and "artificial"
  # groups), so relying on it here silently produced realm = NA for every
  # row of a realm = "terrestrial" (or "artificial") scheme even though the
  # caller had explicitly said which realm it was. When realm is NULL (all
  # realms requested), the per-L1-group mapping is still needed since rows
  # span more than one realm.
  rows_l1 <- if (length(selected_l1) > 0L) {
    data.frame(
      l1_name = selected_l1,
      l2_name = NA_character_,
      l2_code = NA_character_,
      realm = if (!is.null(realm)) realm else .l1_to_realm(selected_l1),
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }

  rows_l2 <- if (!is.null(l2_rows) && nrow(l2_rows) > 0L) {
    data.frame(
      l1_name = l2_rows$l1_name,
      l2_name = l2_rows$l2_name,
      l2_code = l2_rows$l2_code,
      realm = if (!is.null(realm)) realm else .l1_to_realm(l2_rows$l1_name),
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }

  scheme <- rbind(rows_l1, rows_l2)

  # ---------------------------------------------------------------------------
  # Step 6: print discovery summary and return
  # ---------------------------------------------------------------------------
  n_l1_cols <- if (!is.null(rows_l1)) nrow(rows_l1) else 0L
  n_l2_cols <- if (!is.null(rows_l2)) nrow(rows_l2) else 0L

  cat("<iucn_scheme>\n")
  if (!is.null(realm)) cat(sprintf("  Realm:    %s\n", realm))
  cat(sprintf("  L1 cols:  %d  (fallback group names)\n", n_l1_cols))
  cat(sprintf("  L2 cols:  %d  (subcategory names)\n", n_l2_cols))
  cat(sprintf("  Total:    %d habitat columns\n", n_l1_cols + n_l2_cols))

  if (n_l1_cols > 0L) {
    cat("\nL1 GROUPS (single-level / fallback):\n")
    cat(paste(sprintf("  %s", rows_l1$l1_name), collapse = "\n"), "\n")
  }
  if (n_l2_cols > 0L) {
    cat("\nL2 SUBCATEGORIES (grouped by L1 parent):\n")
    for (grp in unique(rows_l2$l1_name)) {
      sub <- rows_l2[rows_l2$l1_name == grp, , drop = FALSE]
      cat(sprintf("  [%s]\n", grp))
      cat(paste(
        sprintf(
          "    %s  %s",
          ifelse(is.na(sub$l2_code), "    ", sub$l2_code),
          sub$l2_name
        ),
        collapse = "\n"
      ), "\n")
    }
  }
  cat("\nPass to build_habitat_prompt(taxa, habitat_scheme = scheme)\n")

  invisible(scheme)
}


#' Build a Habitat Scheme Generation Prompt
#'
#' Asks an LLM to propose a compact, ecologically appropriate set of habitat
#' categories for a given taxon list. The suggested scheme is then passed to
#' \code{\link{build_habitat_prompt}} as \code{habitat_scheme}, replacing the
#' need for a user-supplied custom scheme or the full IUCN classification.
#'
#' This is the recommended starting point when you do not have a pre-existing
#' habitat scheme. The LLM scales the number and specificity of categories to
#' the ecological diversity of the taxon list -- a single-community dataset gets
#' 3-5 focused categories; a mixed multi-realm dataset gets 7-10 broader ones.
#'
#' @param taxon_list Character vector of scientific names.
#' @param min_habitats Integer. Minimum number of habitat categories to
#'   generate. Default \code{2L}.
#' @param max_habitats Integer. Maximum number of habitat categories to
#'   generate. Default \code{10L}. Reduce to force coarser resolution;
#'   increase if the LLM is merging ecologically distinct habitats.
#' @param realm Character or \code{NULL}. Optional hint to constrain the
#'   scheme to a single ecological realm: \code{"marine"},
#'   \code{"freshwater"}, or \code{"terrestrial"}. Use when all taxa are
#'   known to belong to one realm and you want to prevent the LLM from
#'   generating irrelevant cross-realm categories. Default \code{NULL}
#'   (no constraint; the LLM infers realm from the taxon list).
#'
#' @return An object of class \code{c("scheme_prompt", "llm_prompt")} with
#'   elements:
#'   \describe{
#'     \item{prompts}{List of length 1 containing the prompt string.}
#'     \item{taxa}{The deduplicated taxon list.}
#'     \item{chunks}{List of length 1.}
#'     \item{min_habitats}{The minimum supplied.}
#'     \item{max_habitats}{The maximum supplied.}
#'     \item{realm}{The realm hint supplied (or \code{NULL}).}
#'     \item{n_chunks}{Always \code{1L}.}
#'     \item{n_items}{Number of taxa.}
#'   }
#'   Pass to \code{\link[TaxaTools]{prompt_api}} or \code{\link[TaxaTools]{prompt_manual}},
#'   then pass the raw response to \code{\link{parse_scheme_response}}.
#'
#' @details
#' \strong{Reproducibility:} Because the LLM generates the scheme, two runs
#' on the same taxon list may produce slightly different category names. The
#' generated scheme is stored in the \code{habitat_prompt} object returned by
#' \code{\link{parse_scheme_response}} and printed for inspection. Review and
#' edit it before proceeding to the weighted assignment step if exact
#' reproducibility matters.
#'
#' \strong{Full auto-scheme workflow:}
#' \preformatted{
#' # Stage 0: generate scheme
#' sp       <- build_scheme_prompt(taxa_in_data)
#' scheme   <- parse_scheme_response(TaxaTools::prompt_api(sp), sp)
#' print(scheme)   # inspect suggested categories
#'
#' # Stage 1: weighted assignment (scheme flows through automatically)
#' prompt   <- build_habitat_prompt(taxa_in_data, habitat_scheme = scheme)
#' raw_text <- TaxaTools::prompt_api(prompt)
#' hab_tbl  <- parse_hierarchical_habitat_response(raw_text, taxa_in_data,
#'                                                 habitat_scheme = prompt)
#' }
#'
#' @seealso \code{\link{parse_scheme_response}},
#'   \code{\link{build_habitat_prompt}},
#'   \code{\link{example_habitat_scheme}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' taxa <- unique(occurrence_data$taxon_name)
#' sp <- build_scheme_prompt(taxa, realm = "marine")
#' print(sp)
#' raw <- TaxaTools::prompt_api(sp)
#' scheme <- parse_scheme_response(raw, sp)
#' print(scheme)
#' }
build_scheme_prompt <- function(taxon_list,
                                min_habitats = 2L,
                                max_habitats = 10L,
                                realm = NULL) {
  if (!is.character(taxon_list) || length(taxon_list) == 0) {
    stop("build_scheme_prompt: 'taxon_list' must be a non-empty character vector.")
  }
  if (!is.numeric(min_habitats) || min_habitats < 1) {
    stop("build_scheme_prompt: 'min_habitats' must be a positive integer.")
  }
  if (!is.numeric(max_habitats) || max_habitats < min_habitats) {
    stop("build_scheme_prompt: 'max_habitats' must be >= 'min_habitats'.")
  }
  if (!is.null(realm)) {
    valid_realms <- c("marine", "freshwater", "terrestrial")
    if (!realm %in% valid_realms) {
      stop(sprintf(
        "build_scheme_prompt: 'realm' must be one of: %s, or NULL.",
        paste(valid_realms, collapse = ", ")
      ))
    }
  }

  taxon_list <- unique(trimws(taxon_list))
  taxon_list <- taxon_list[nzchar(taxon_list)]
  min_habitats <- as.integer(min_habitats)
  max_habitats <- as.integer(max_habitats)

  species_block <- paste(paste0('"', taxon_list, '"'), collapse = ", ")

  realm_instruction <- if (!is.null(realm)) {
    sprintf(
      "All species in this list belong to the %s realm. ",
      realm
    )
  } else {
    ""
  }

  prompt_str <- paste0(
    "Act as an expert ecologist and taxonomist.\n\n",
    "I will provide a list of species. Your task is to propose a compact set ",
    "of habitat categories that together cover the ecological diversity of this ",
    "community. These categories will be used as predictors in a statistical ",
    "model, so they should be:\n",
    "  - Mutually exclusive (a species clearly belongs to one primary category)\n",
    "  - Collectively exhaustive for this community\n",
    "  - All at the same ecological scale (do not mix broad and fine categories)\n",
    "  - Plain English, suitable as factor level names (no special characters)\n\n",
    "IMPORTANT -- MACROHABITAT SCALE ONLY:\n",
    "Categories must describe the ecosystem or macrohabitat type, NOT the ",
    "microhabitat or substrate the species physically occupies within it. ",
    "For example: a species that lives in burrows within an estuary belongs to ",
    "an ESTUARINE category, not a 'burrow' or 'subterranean' category. ",
    "A species that lives in kelp holdfasts on a rocky reef belongs to a ",
    "ROCKY REEF category, not a 'crevice' or 'cave' category. ",
    "Valid examples: Rocky Reef, Sandy Subtidal, Estuary, Kelp Forest, ",
    "Pelagic, Freshwater Stream, Wetland, Grassland, Forest. ",
    "Invalid examples: Burrow, Cave, Crevice, Root Zone, Interstitial -- ",
    "these are microhabitats within a macrohabitat, not categories.\n\n",
    realm_instruction,
    sprintf(
      "Propose between %d and %d habitat categories. ",
      min_habitats, max_habitats
    ),
    "Fewer categories are better when species ecology is similar; ",
    "use more only when the community genuinely spans distinct habitats.\n\n",
    "OUTPUT FORMAT: Return ONLY a raw CSV block with exactly two columns and ",
    "no preamble or postamble:\n",
    "  habitat_name  -- your proposed category name (plain English)\n",
    if (!is.null(realm)) {
      sprintf(
        "  realm         -- always \"%s\" (all species in this list are in the %s realm)\n\n",
        realm, realm
      )
    } else {
      "  realm         -- one of: marine, freshwater, terrestrial, or NA if mixed\n\n"
    },
    "The first line must be the header: habitat_name,realm\n",
    "Each subsequent line is one habitat category.\n\n",
    "SPECIES LIST:\n",
    species_block
  )

  structure(
    list(
      prompts      = list(prompt_str),
      taxa         = taxon_list,
      chunks       = list(taxon_list),
      min_habitats = min_habitats,
      max_habitats = max_habitats,
      realm        = realm,
      n_chunks     = 1L,
      n_items      = length(taxon_list)
    ),
    class = c("scheme_prompt", "llm_prompt")
  )
}


#' Print a scheme_prompt Object
#'
#' @param x A \code{scheme_prompt} object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export
print.scheme_prompt <- function(x, ...) {
  cat("<scheme_prompt>\n")
  cat(sprintf("  Taxa:         %d species\n", length(x$taxa)))
  cat(sprintf(
    "  Habitats:     %d to %d categories requested\n",
    x$min_habitats, x$max_habitats
  ))
  if (!is.null(x$realm)) {
    cat(sprintf("  Realm hint:   %s\n", x$realm))
  } else {
    cat("  Realm hint:   (none -- LLM infers from taxa)\n")
  }
  cat(sprintf(
    "  Prompt tokens (approx): ~%d\n",
    nchar(x$prompts[[1]]) %/% 4L
  ))
  invisible(x)
}


# ==============================================================================
# parse_scheme_response() -- parse LLM-generated habitat scheme
# ==============================================================================

#' Parse a Habitat Scheme Response from an LLM
#'
#' Parses the raw CSV text returned by an LLM in response to a
#' \code{\link{build_scheme_prompt}} prompt into a \code{habitat_scheme}
#' dataframe ready for \code{\link{build_habitat_prompt}}.
#'
#' @param raw_text Character. Raw LLM response from
#'   \code{\link[TaxaTools]{prompt_api}} or \code{\link[TaxaTools]{read_llm_response}}.
#' @param scheme_prompt A \code{scheme_prompt} object from
#'   \code{\link{build_scheme_prompt}}. Used to validate the response against
#'   the requested min/max habitat counts. If \code{NULL}, validation is
#'   skipped.
#'
#' @return A \code{habitat_scheme} data.frame with columns \code{l1_name}
#'   and \code{realm}, suitable for passing directly to
#'   \code{\link{build_habitat_prompt}} as \code{habitat_scheme}. The
#'   \code{l2_name} and \code{l2_code} columns are set to \code{NA}
#'   (single-level scheme). Print the result to inspect and verify the
#'   suggested categories before proceeding.
#'
#' @details
#' The returned dataframe is a standard single-level \code{habitat_scheme}.
#' Edit it in R before passing to \code{\link{build_habitat_prompt}} if you
#' want to rename, merge, or split categories:
#' \preformatted{
#' scheme <- parse_scheme_response(raw, sp)
#' print(scheme)
#'
#' # Edit if needed:
#' scheme$l1_name[scheme$l1_name == "Rocky Reef"] <- "Rocky Subtidal"
#'
#' # Then use as normal:
#' prompt <- build_habitat_prompt(taxa, habitat_scheme = scheme)
#' }
#'
#' @seealso \code{\link{build_scheme_prompt}}, \code{\link{build_habitat_prompt}}
#'
#' @importFrom utils read.csv
#' @export
#'
#' @examples
#' \dontrun{
#' sp <- build_scheme_prompt(taxa, realm = "marine")
#' raw <- TaxaTools::prompt_api(sp)
#' scheme <- parse_scheme_response(raw, sp)
#' print(scheme)
#' }
parse_scheme_response <- function(raw_text, scheme_prompt = NULL) {
  if (!is.character(raw_text) || length(raw_text) != 1L ||
    !nzchar(trimws(raw_text))) {
    stop("parse_scheme_response: 'raw_text' must be a length-1 non-empty string.")
  }

  min_h <- if (inherits(scheme_prompt, "scheme_prompt")) scheme_prompt$min_habitats else 1L
  max_h <- if (inherits(scheme_prompt, "scheme_prompt")) scheme_prompt$max_habitats else Inf

  # Strip markdown fences
  txt <- gsub("```[a-zA-Z]*\n?", "", raw_text)
  txt <- gsub("```", "", txt)

  # Find header row containing habitat_name
  lines <- trimws(strsplit(txt, "\n")[[1]])
  lines <- lines[nzchar(lines)]
  hdr_idx <- which(grepl("habitat_name", lines, ignore.case = TRUE) &
    grepl(",", lines, fixed = TRUE))[1]

  if (is.na(hdr_idx)) {
    stop(
      "parse_scheme_response: could not find a header row containing ",
      "'habitat_name'. Check the LLM response."
    )
  }

  # Trim preamble/postamble
  lines <- lines[hdr_idx:length(lines)]
  is_data <- grepl(",", lines, fixed = TRUE) | seq_along(lines) == 1L
  lines <- lines[1:max(which(is_data))]

  # Strip duplicate headers (shouldn't happen for single-chunk but be safe)
  header <- lines[1L]
  lines <- c(header, lines[-1L][lines[-1L] != header])

  parsed <- tryCatch(
    utils::read.csv(
      text = paste(lines, collapse = "\n"),
      stringsAsFactors = FALSE, strip.white = TRUE,
      na.strings = c("", "NA", "N/A")
    ),
    error = function(e) {
      stop("parse_scheme_response: CSV parsing failed: ", e$message, call. = FALSE)
    }
  )

  if (nrow(parsed) == 0L) {
    stop("parse_scheme_response: response parsed successfully but contains no rows.")
  }

  # Normalise column name (allow habitat_name or name)
  if (!"habitat_name" %in% names(parsed)) {
    alt <- grep("name|habitat", names(parsed), ignore.case = TRUE, value = TRUE)[1]
    if (!is.na(alt)) {
      names(parsed)[names(parsed) == alt] <- "habitat_name"
    } else {
      stop("parse_scheme_response: could not identify a 'habitat_name' column.")
    }
  }

  # Clean habitat names
  parsed$habitat_name <- trimws(as.character(parsed$habitat_name))
  parsed <- parsed[nzchar(parsed$habitat_name), , drop = FALSE]

  # Validate count
  n_cats <- nrow(parsed)
  if (n_cats < min_h) {
    warning(sprintf(
      "parse_scheme_response: LLM returned %d category/categories, fewer than min_habitats = %d.",
      n_cats, min_h
    ), call. = FALSE)
  }
  if (n_cats > max_h) {
    warning(sprintf(
      "parse_scheme_response: LLM returned %d categories, more than max_habitats = %d. ",
      n_cats, max_h
    ), call. = FALSE)
  }

  # Validate realm column
  valid_realms <- c("marine", "freshwater", "terrestrial", NA)
  if ("realm" %in% names(parsed)) {
    parsed$realm <- trimws(tolower(as.character(parsed$realm)))
    parsed$realm[parsed$realm == "na" | parsed$realm == ""] <- NA_character_
    bad <- !parsed$realm %in% valid_realms
    if (any(bad)) {
      warning(sprintf(
        "parse_scheme_response: unrecognised realm value(s) set to NA: %s",
        paste(unique(parsed$realm[bad]), collapse = ", ")
      ), call. = FALSE)
      parsed$realm[bad] <- NA_character_
    }
  } else {
    parsed$realm <- NA_character_
  }

  # Build habitat_scheme dataframe
  scheme <- data.frame(
    l1_name = parsed$habitat_name,
    l2_name = NA_character_,
    l2_code = NA_character_,
    realm = parsed$realm,
    stringsAsFactors = FALSE
  )

  # Print a clear summary so the user can inspect before proceeding
  message(sprintf(
    "parse_scheme_response: %d habitat categories generated.", n_cats
  ))
  message("  Inspect with print(scheme) before passing to build_habitat_prompt().")

  scheme
}
