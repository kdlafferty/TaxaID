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
# Audited row-by-row against the real IUCN Habitats Classification Scheme
# v3.1 source document (fetched directly, not from memory). Shrubland's real
# 3.1-3.3 order is Subarctic/Subantarctic/Boreal (not Forest's
# Boreal/Subarctic/Subantarctic order). See each inline comment below for
# further scheme-specific notes.
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
    # Wetlands (inland) -- 18 real subcategories (5.1-5.18); 5.18 is "Karst
    # and Other Subterranean Inland Aquatic Systems".
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
    # peaks, talus, feldmark" only as prose examples).
    NA_character_,
    # Caves
    "Dry Caves", "Other Dry Subterranean Habitats",
    # Desert
    "Hot", "Temperate", "Cold",
    # Marine Neritic -- codes 9.1-9.10, verified directly against the IUCN
    # source document. Note: Seamount is real code 11.5, under Marine Deep
    # Ocean Floor, not Marine Neritic, despite the naming similarity to
    # "Seamounts and Knolls".
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
    # Marine Deep Ocean Floor -- real 11.3 is "Abyssal Mountain/Hills"; real
    # 11.4 ("Hadal/Deep Sea Trench") starts at >6000m; "Seamount" is its own
    # real code, 11.5.
    "Continental Slope/Bathyal Zone (200-4000m)",
    "Abyssal Plain",
    "Abyssal Mountain/Hills",
    "Hadal/Deep Sea Trench (>6000m)",
    "Seamount",
    "Deep Sea Vents (Rifts/Seeps)",
    # Marine Intertidal -- real 12.4 is "Mud Shoreline and Intertidal Mud
    # Flats".
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
    # Artificial - Aquatic -- codes 15.1-15.13.
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
    # specified").
    NA_character_,
    # Other -- L1-only in the real scheme.
    NA_character_,
    # Unknown -- L1-only in the real scheme.
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
#' @param compound_sep \code{NULL} (default) or a single string, e.g. \code{"-"}.
#'   When supplied, any single-level scheme label that contains it is read as
#'   a COMPOUND of the parts it joins: \code{"Coastal-Marine-Estuary-Stream"}
#'   is the union of Coastal, Marine, Estuary and Stream. The LLM is then asked
#'   to weight each distinct part as a habitat column of its own (alongside the
#'   scheme's plain labels), and the compound label's weight is derived by
#'   \code{\link{parse_hierarchical_habitat_response}} as the MAXIMUM over its
#'   parts. See the section \emph{Compound labels}. Only single-level schemes
#'   may carry compounds; a two-level scheme with \code{compound_sep} errors.
#' @param compound_rule \code{"sum"} (default) or \code{"max"}: how a compound
#'   label's weight is derived from its parts. The parts are disjoint shares of
#'   the species' habitat use that sum to 1 with the plain labels, so the
#'   union's share is their SUM (capped at 1); \code{"max"} takes the largest
#'   part instead, which never falls below a component either but discards the
#'   other parts' shares. Ignored when \code{compound_sep} is \code{NULL}.
#' @param habitat_scheme A dataframe defining the habitat classification to use,
#'   the string \code{"IUCN_L1"}, or \code{NULL}.
#'   \code{NULL} (default) uses a simple three-category scheme:
#'   Marine, Freshwater, Terrestrial. This is always a valid starting point
#'   and is always interpretable in a model.
#'   \code{"IUCN_L1"} uses the 18 IUCN Level 1 group names as a
#'   single-level scheme. Pass a dataframe for a custom scheme (must contain
#'   \code{l1_name}; optional: \code{l2_name}, \code{l2_code}, \code{realm}).
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
#'
#' @section Compound labels:
#' A scheme label that names several habitats at once (\code{"Coastal-Marine-
#' Estuary-Stream"} for a stream-fed lagoon) is one column to the model, and a
#' model scores one column as one habitat: in practice it reads the marine words
#' and ignores the rest, so a stream fish can score \emph{lower} on the compound
#' than on \code{"Coastal-Stream"}, a label the compound contains. With
#' \code{compound_sep} the model never sees the compound as a scorable column.
#' It weights the parts, and a species that uses ANY part of a site uses the
#' site, so the compound's weight is the SUM of its parts' shares, capped at 1
#' (\code{compound_rule = "sum"}): it is never below any component, by
#' construction. The alternative \code{"max"} keeps only the largest part;
#' because the model's sum-to-1 budget is spread over more columns once a
#' compound is split, \code{"max"} systematically LOWERS the compound for the
#' species that use several of its parts (an estuarine resident scored 0.3
#' Coastal + 0.5 Estuary + 0.1 Marine reads 0.5 under max, 0.9 under sum).
#' The derived column is NOT part of the sum-to-1 constraint (the parts are), so
#' a lookup built this way has scheme columns that can sum above 1; every
#' consumer in this ecosystem reads a weight as a per-habitat affinity, not as
#' a share, so that is harmless, and the breadth statistic renormalises. One
#' caveat to declare rather than hide: a part that is a modifier rather than a
#' habitat ("Coastal" in "Coastal-Stream") is scored as the habitat it names,
#' and a marine species then carries its coastal share into every compound
#' that lists it. The returned object records the mapping in
#' \code{$compounds} and the scheme's own labels in \code{$scheme_cols};
#' \code{$habitat_cols} is what the model is asked to output. A part that is
#' also a plain scheme label is asked once and serves both.
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
  geographic_context = NULL,
  compound_sep = NULL,
  compound_rule = c("sum", "max")
) {
  compound_rule <- match.arg(compound_rule)
  if (!is.character(taxon_list) || length(taxon_list) == 0) {
    stop("build_habitat_prompt: 'taxon_list' must be a non-empty character vector.")
  }
  if (!is.null(compound_sep)) {
    if (!is.character(compound_sep) || length(compound_sep) != 1L ||
      is.na(compound_sep) || !nzchar(compound_sep)) {
      stop("build_habitat_prompt: 'compound_sep' must be NULL or a single non-empty string.")
    }
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
    # For finer resolution pass "IUCN_L1" or supply a custom scheme.
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
  # Mixed schemes (both L1 and L2 rows):
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

  # Compound labels: the scheme's own labels are what consumers read back
  # (scheme_cols); the columns the model is asked for (habitat_cols) replace
  # each compound by its parts. See the "Compound labels" section.
  scheme_cols <- habitat_cols
  compounds <- list()
  if (!is.null(compound_sep)) {
    if (has_l2_rows) {
      stop(
        "build_habitat_prompt: 'compound_sep' is only supported for a ",
        "single-level scheme (l1_name only)."
      )
    }
    sp <- .split_compound_levels(habitat_cols, compound_sep)
    compounds <- sp$compounds
    habitat_cols <- sp$asked
  }

  chunks <- split(taxon_list, ceiling(seq_along(taxon_list) / chunk_size))
  n_chunks <- length(chunks)

  prompts <- lapply(chunks, function(chunk_taxa) {
    .build_single_prompt(
      chunk_taxa, extra_covariates, scheme, habitat_cols,
      geographic_context, compounds
    )
  })

  structure(
    list(
      prompts            = prompts,
      taxa               = taxon_list,
      chunks             = chunks,
      scheme             = scheme,
      habitat_cols       = habitat_cols,
      scheme_cols        = scheme_cols,
      compounds          = compounds,
      compound_sep       = compound_sep,
      compound_rule      = compound_rule,
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
  if (length(x$compounds %||% list()) > 0L) {
    cat(sprintf(
      "  Compounds:   %d scheme label(s) derived as the %s over their parts\n",
      length(x$compounds), x$compound_rule %||% "sum"
    ))
  }
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
                                 geographic_context = NULL, compounds = list()) {
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
  # and mixed schemes carrying both L1 fallback rows and L2 rows.
  two_level <- .is_two_level(scheme)

  if (two_level) {
    # A mixed-scale scheme (both L1 fallback rows and L2 rows present) has l2_name = NA on its L1-only
    # rows -- display_name falls back to l1_name for those specific rows
    # so the prompt shows the real group name instead of literal "NA".
    # Without this fallback, build_habitat_prompt() would send
    # "NA  [Forest]", "NA  [Savanna]", etc. to the LLM for every L1 fallback
    # row.
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
  } else if (length(compounds) > 0L) {
    # The model is asked for the PARTS of each compound label, never for the
    # compound itself; each part is annotated with the label(s) it belongs to
    # so a modifier such as "Coastal" is read in its scheme context.
    part_of <- vapply(habitat_cols, function(h) {
      owners <- names(compounds)[vapply(compounds, function(cc) h %in% cc, logical(1))]
      if (length(owners) == 0L) "" else paste0("  [part of: ", paste(owners, collapse = "; "), "]")
    }, character(1))
    hab_block <- paste(sprintf("  %s%s", habitat_cols, part_of), collapse = "\n")
    class_header <- paste0(
      "HABITAT CLASSES:\n",
      "(the classification uses compound labels; each compound is listed here ",
      "as its component habitats, and you score the COMPONENTS)\n"
    )
    col_note <- paste0(
      "The column name for each habitat is its exact name as listed above ",
      "(e.g. '", habitat_cols[1], "').\n",
      "COMPOUND LABELS: ",
      paste(vapply(names(compounds), function(cn) {
        sprintf("'%s' = %s", cn, paste(compounds[[cn]], collapse = " + "))
      }, character(1)), collapse = "; "),
      ". Do NOT output a column for a compound label; its weight is derived ",
      "afterwards from its components. Score each component as ",
      "the habitat it names, in the context of the compound(s) it belongs to.\n\n"
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
# .split_compound_levels() -- internal helper
# ==============================================================================

#' Split compound scheme labels into the columns the model is asked for
#'
#' A label containing `sep` with at least two non-empty parts is a compound.
#' Returns `asked` (plain labels plus the distinct parts, in first-seen scheme
#' order, each once) and `compounds` (a named list, compound -> its parts).
#' A label with `sep` but fewer than two non-empty parts is kept as a plain
#' label.
#' @noRd
.split_compound_levels <- function(levels, sep) {
  compounds <- list()
  asked <- character(0)
  for (lv in levels) {
    parts <- trimws(strsplit(lv, sep, fixed = TRUE)[[1L]])
    parts <- unique(parts[nzchar(parts)])
    if (grepl(sep, lv, fixed = TRUE) && length(parts) >= 2L) {
      compounds[[lv]] <- parts
      asked <- c(asked, parts)
    } else {
      asked <- c(asked, lv)
    }
  }
  list(asked = unique(asked), compounds = compounds)
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
#' This single check is sufficient: every scheme reaching this function has
#' already passed through \code{.validate_habitat_scheme()}, which subsets
#' to \code{c("l1_name", "l2_code", "l2_name", "realm")} and never preserves
#' an \code{l1_code} column, so neither an \code{identical()} comparison
#' against the raw (differently-shaped) \code{.iucn_habitat_lookup} nor an
#' \code{l1_code} membership check could ever succeed here. Confirmed via
#' the column set every validated scheme carries (only
#' \code{l1_name}/\code{l2_name}/\code{l2_code}/\code{realm}) and a grep of
#' every call site.
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
