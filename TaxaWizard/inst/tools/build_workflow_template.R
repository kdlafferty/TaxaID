# =============================================================================
# build_workflow_template.R -- generate inst/TaxaID_Workflow_Template.R
#
# The template is DERIVED, not written by hand.
#
# WHY. This monorepo has had two workflow templates, and both have sat
# unrunnable for months while looking maintained: the package-level one
# called seven functions that are retired, and the canonical one fell
# behind on four subsystems. A hand-written template rots silently
# because nothing compares it to the code it claims to demonstrate.
#
# So this one is assembled from the workflow graph's own snippets -- the same
# files TaxaWizard generates scripts from, already guarded by
# .validate_snippets(), which asserts every call and named argument exists in
# the installed packages. A test regenerates the template and compares, so a
# snippet change that is not reflected here fails the build instead of quietly
# making the template wrong.
#
# Run:  Rscript TaxaWizard/inst/tools/build_workflow_template.R
# =============================================================================

.libPaths(c(path.expand("~/Library/R/4.0/library"), .libPaths()))
suppressMessages(library(TaxaWizard))

ROOT <- Sys.getenv("TAXAID_ROOT", normalizePath("."))
# The guard test regenerates to a temp file and compares, so the destination is
# overridable. Default is the committed location.
OUT  <- Sys.getenv("TAXAID_TEMPLATE_OUT",
                   file.path(ROOT, "inst", "TaxaID_Workflow_Template.R"))

# The canonical single-site path: raw sequences through to reviewed assignments.
# Taken from the graph rather than typed: .compute_paths("sequences","reviewed")
# returns this as the kernel-priors, per-group route.
CANONICAL_PATH <- c(
  "seq_to_match", "match_to_taxa", "taxa_to_refs", "refs_to_matrix",
  "matrix_to_model", "model_match_to_lik", "taxa_to_occ", "occ_to_std",
  "dist_to_priors_by_group", "lik_prior_to_post", "post_to_consensus",
  "taxa_to_context", "consensus_to_reviewed"
)

# Config placeholders -> Section 0 constant, default, and what it means.
# This is the ONE hand-maintained table in the file. A placeholder that appears
# in a snippet and is missing here stops the build loudly (see below), so the
# table cannot silently fall behind the snippets.
CONFIG <- list(
  marker            = list("MARKER",            '"MiFish-U"',        "Primer/marker name, as your lab records it"),
  barcode_term      = list("BARCODE_TERM",      '"12S"',             "NCBI barcode search term for this marker"),
  target_group      = list("TARGET_GROUP",      '"fish"',            "Free-text taxonomic scope of the assay"),
  data_type         = list("DATA_TYPE",         '"eDNA"',            'Observation signal, passed to review_assignments()/review_spatial_context(); must be one of "eDNA", "acoustic" or "image"'),
  email             = list("NCBI_EMAIL",        'Sys.getenv("ENTREZ_EMAIL")', "Required by NCBI for Entrez queries"),
  lat               = list("SITE_LAT",          "0",                 "Site latitude, decimal degrees"),
  lon               = list("SITE_LON",          "0",                 "Site longitude, decimal degrees"),
  site_habitat      = list("SITE_HABITAT",      '"Marine"',          "Habitat of the sampling site itself"),
  main_habitat      = list("SITE_HABITAT",      '"Marine"',          "Same as SITE_HABITAT; the graph names it twice"),
  habitat_scheme    = list("HABITAT_SCHEME",    "NULL",              "Habitat vocabulary; NULL uses the package default"),
  geographic_hint   = list("GEOGRAPHIC_HINT",   '"the study region"', "Plain-language region, used in LLM prompts"),
  date              = list("SAMPLING_DATE",     "Sys.Date()",        "Sampling date, or Sys.Date() if not recorded"),
  year_range        = list("YEAR_RANGE",        '"1995,2025"',       "Occurrence year window; set it, do not inherit a default"),
  search_radius_deg = list("SEARCH_RADIUS_DEG", "2",                 "Occurrence search radius around the site, degrees"),
  gbif_limit        = list("GBIF_LIMIT",        "50000",             "Cap on occurrence records fetched"),
  backbone_id       = list("BACKBONE_ID",       "11",                "Source taxonomic backbone id"),
  target_backbone_id= list("TARGET_BACKBONE_ID","11",                "Backbone to harmonise onto"),
  rank_system       = list("RANK_SYSTEM",       "NULL",              "Rank columns; NULL auto-detects"),
  taxon_col         = list("TAXON_COL",         '"taxon_name"',      "Column holding the taxon name"),
  taxon_rank_col    = list("TAXON_RANK_COL",    '"taxon_name_rank"', "Column holding that name's rank"),
  sampling_group_col= list("SAMPLING_GROUP_COL",'"sampling_group"',  "Detection-process grouping; see the note in Section 0"),
  min_score         = list("MIN_SCORE",         "0",                 "Minimum match score to keep"),
  min_abundance     = list("MIN_ABUNDANCE",     "1",                 "Minimum read count to keep"),
  cumulative_threshold = list("CUMULATIVE_THRESHOLD", "0.99",        "Cumulative posterior mass retained per observation"),
  blast_method      = list("BLAST_METHOD",      '"remote"',          '"remote" needs no local BLAST install'),
  llm_fn            = list("LLM_FN",            "TaxaTools::call_api", "Function used for every LLM call"),
  gbif_cache_dir    = list("GBIF_CACHE_DIR",    'file.path(CACHE_ROOT, "gbif")',      "Occurrence cache"),
  habitat_cache_dir = list("HABITAT_CACHE_DIR", 'file.path(CACHE_ROOT, "habitat")',   "Habitat-classification cache"),
  reference_cache_dir = list("REFERENCE_CACHE_DIR", 'file.path(CACHE_ROOT, "reference")', "Reference-sequence cache"),
  review_cache_dir  = list("REVIEW_CACHE_DIR",  'file.path(CACHE_ROOT, "review")',    "LLM review cache"),
  inat_cache_dir    = list("INAT_CACHE_DIR",    'file.path(CACHE_ROOT, "inat")',      "iNaturalist range cache"),
  include_domestic_priors = list("INCLUDE_DOMESTIC_PRIORS", "FALSE", "Add domestic/food-species priors"),
  include_group_priors    = list("INCLUDE_GROUP_PRIORS",    "TRUE",  "Add group-level prior support"),
  include_downranking     = list("INCLUDE_DOWNRANKING",     "TRUE",  "Allow posterior downranking"),
  include_evidence_block  = list("INCLUDE_EVIDENCE_BLOCK",  "FALSE", "Curve-priced evidence for unobserved taxa"),
  screen_reference_accessions = list("SCREEN_REFERENCE_ACCESSIONS", "FALSE", "Screen reference accessions for errors; off by default -- see the comment in Step 1 for why"),
  review_flagged_references   = list("REVIEW_FLAGGED_REFERENCES",   "TRUE", "Send flagged accessions for LLM review"),
  remove_incongruent_references = list("REMOVE_INCONGRUENT_REFERENCES", "TRUE", "Drop references failing hierarchy congruence"),
  invasive_taxa     = list("INVASIVE_TAXA",     "NULL",              "Watch-list taxon names, or NULL"),
  invasive_watch_p_conc = list("INVASIVE_WATCH_P_CONC", "0.9",       "Concentration for watch-list evidence"),
  match_list_taxa   = list("MATCH_LIST_TAXA",   "NULL",              "Candidate taxa to evidence-price, or NULL"),
  taxonomy_lookup   = list("TAXONOMY_LOOKUP",   "NULL",              "Optional taxonomy table for evidence rows"),
  plot_theta_surface_taxon = list("PLOT_THETA_SURFACE_TAXON", "NULL", "Taxon to render a prior field for, or NULL")
)

# Dataflow placeholders: resolved from the graph's own edge wiring, never typed.
DATAFLOW <- c(
  input_var = NA, match_var = "match_df", model_var = "model_params",
  lik_var = "likelihoods", priors_var = "priors",
  taxaexpect_priors_var = "priors", consensus_var = "consensus",
  context_var = "context_df", taxonomy_map_var = "taxa",
  habitat_lookup_var = "habitat_lookup", site_table_var = "site_table"
)

# The graph and its snippets come from the repository under ROOT when it holds
# them (the generator is run from the repository root, and the guard test sets
# TAXAID_ROOT to it), and from the installed TaxaWizard otherwise. Reading them
# from the installed copy while the repository's own snippets had changed made
# the guard test compare the committed template with a stale generation.
SRC_GRAPH_DIR <- file.path(ROOT, "TaxaWizard", "inst", "graph")
if (dir.exists(file.path(SRC_GRAPH_DIR, "snippets"))) {
  GRAPH_DIR <- SRC_GRAPH_DIR
  graph <- jsonlite::fromJSON(file.path(GRAPH_DIR, "workflow_graph.json"), simplifyVector = FALSE)
} else {
  GRAPH_DIR <- system.file("graph", package = "TaxaWizard")
  graph <- TaxaWizard:::.load_graph()
}
SNIPPET_DIR <- file.path(GRAPH_DIR, "snippets")
edge_by_id <- stats::setNames(graph$edges, vapply(graph$edges, function(e) e$id, ""))

used_config <- character(0)
missing_ph  <- character(0)
body_lines  <- character(0)

for (i in seq_along(CANONICAL_PATH)) {
  eid <- CANONICAL_PATH[i]
  edge <- edge_by_id[[eid]]
  f <- file.path(SNIPPET_DIR, paste0(eid, ".R"))
  if (!file.exists(f)) stop("no snippet for edge: ", eid, call. = FALSE)
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")

  input_node <- unlist(edge$from)[1]

  for (ph in unique(unlist(regmatches(txt, gregexpr("\\{\\{[a-zA-Z_0-9]+\\}\\}", txt))))) {
    key <- gsub("[{}]", "", ph)
    if (key %in% names(DATAFLOW)) {
      repl <- if (identical(key, "input_var")) input_node else unname(DATAFLOW[[key]])
    } else if (key %in% names(CONFIG)) {
      repl <- CONFIG[[key]][[1]]
      used_config <- c(used_config, key)
    } else {
      missing_ph <- c(missing_ph, key)
      next
    }
    txt <- gsub(ph, repl, txt, fixed = TRUE)
  }

  body_lines <- c(
    body_lines, "",
    "# =============================================================================",
    sprintf("# STEP %d of %d -- %s", i, length(CANONICAL_PATH), edge$label %||% eid),
    sprintf("#   edge: %s    %s -> %s", eid,
            paste(unlist(edge$from), collapse = " + "), paste(unlist(edge$to), collapse = " + ")),
    if (!is.null(edge$duration)) sprintf("#   typical cost: %s", edge$duration) else NULL,
    "# =============================================================================",
    strsplit(txt, "\n", fixed = TRUE)[[1]],
    sprintf("%s <- %s", unlist(edge$to)[1], unlist(edge$to)[1])
  )
}

if (length(missing_ph) > 0L) {
  stop("Placeholders used by a snippet but absent from CONFIG/DATAFLOW: ",
       paste(unique(missing_ph), collapse = ", "),
       "\n  Add them to the CONFIG table in TaxaWizard/inst/tools/build_workflow_template.R.",
       call. = FALSE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- Section 0: only the constants this path actually uses -------------------
used_config <- unique(used_config)
seen_const <- character(0)
cfg_lines <- character(0)
for (key in names(CONFIG)) {
  if (!key %in% used_config) next
  const <- CONFIG[[key]][[1]]
  if (const %in% seen_const) next
  seen_const <- c(seen_const, const)
  cfg_lines <- c(cfg_lines, sprintf("%-26s <- %-38s # %s",
                                    const, CONFIG[[key]][[2]], CONFIG[[key]][[3]]))
}

header <- c(
  "# =============================================================================",
  "# TaxaID single-site workflow template",
  "#",
  "# GENERATED FILE -- do not edit by hand.",
  "#   Source:    the workflow graph's own snippets (TaxaWizard/inst/graph/snippets/)",
  "#   Generator: TaxaWizard/inst/tools/build_workflow_template.R",
  "#   Guarded by: TaxaWizard/tests/testthat/test-workflow-template.R, which",
  "#               regenerates this file and fails if it differs.",
  "#",
  "# Every step below is the same code TaxaWizard generates for that edge, so a",
  "# change to a snippet reaches this template or breaks the build. It is derived",
  "# rather than written because BOTH of this project's previous templates sat",
  "# unrunnable for months while looking maintained.",
  "#",
  "# This is a TEMPLATE, not a worked example: it carries no study's data and no",
  "# real paths. Edit Section 0, supply your own inputs, and run top to bottom.",
  "#",
  "# The path it demonstrates (from the graph, sequences -> reviewed):",
  paste0("#   ", paste(CANONICAL_PATH, collapse = " -> ")),
  "# =============================================================================",
  "",
  "library(TaxaTools);  library(TaxaFetch);  library(TaxaHabitat)",
  "library(TaxaMatch);  library(TaxaLikely); library(TaxaExpect)",
  "library(TaxaAssign); library(TaxaFlag)",
  "",
  "# --- Step 0: does this machine have what the path needs? ---------------------",
  "# Stops here rather than failing deep inside a stage.",
  ".setup <- TaxaWizard::workflow_check(",
  sprintf("  edges = c(%s),",
          paste(sprintf('"%s"', CANONICAL_PATH), collapse = ", ")),
  "  verbose = TRUE",
  ")",
  'if (any(.setup$status == "missing")) stop("Setup incomplete -- see the fix column above.")',
  "",
  "# =============================================================================",
  "# 0.  CONFIGURATION  (edit this section only)",
  "# =============================================================================",
  "",
  'CACHE_ROOT <- file.path(tempdir(), "taxaid_cache")   # point at a durable dir for real runs',
  "",
  "# SEQUENCES: the raw input this path starts from. Supply your own.",
  'SEQUENCES <- NULL   # e.g. readRDS("my_esv_table.rds")',
  "",
  cfg_lines,
  "",
  "# sampling_group_col identifies the DETECTION PROCESS a record came from, not",
  "# a taxonomic group. Priors and kernel bandwidth are both estimated within it,",
  "# so pooling unlike processes biases every group toward the largest one.",
  "",
  "sequences <- SEQUENCES",
  'if (is.null(sequences)) stop("Set SEQUENCES in Section 0 before running.", call. = FALSE)'
)

writeLines(c(header, body_lines, "",
             "# =============================================================================",
             "# Workflow complete. `reviewed` holds the final assignments.",
             "# ============================================================================="),
           OUT)

cat("wrote:", OUT, "\n")
cat("  steps:", length(CANONICAL_PATH), " config constants:", length(seen_const),
    " lines:", length(readLines(OUT)), "\n")
