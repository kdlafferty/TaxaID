# Edge: taxa -> occurrences
# Source: TaxaFetch/inst/GBIF_workflow.R + Define_search_workflow.R

key_matches <- TaxaFetch::get_keys_from_context({{input_var}})
# fetch_gbif_occurrences() takes the usageKey COLUMN, not the whole table that
# get_keys_from_context() returns: it begins with as.integer(keys), and a data
# frame cannot be coerced to integer. Passing the table raises
# "'list' object cannot be coerced to type 'integer'".
keys <- key_matches$usageKey[!is.na(key_matches$usageKey)]

# --- Check GBIF match quality BEFORE requesting anything ---------------------
# A populated but WRONG key is worse than a missing one, and neither announces
# itself downstream: fetch_gbif_occurrences() drops NA keys silently, so an
# unresolved taxon leaves the occurrence pool without a word, and a FUZZY or
# HIGHERRANK match fetches a DIFFERENT taxon's records under this taxon's name.
# get_keys_from_context()'s own documentation says to review these matchTypes
# before downstream use; this is that review, and it is deliberately a stop.
# What this does NOT catch: an EXACT, ACCEPTED key whose taxon simply holds no
# occurrences in your area. That key is correct and the gap is real data, so
# only a pre-download COUNT can see it -- a separate check, not this one.
# ERROR and NO_DATA rows carry an NA usageKey, so the NA check below covers
# them too. To proceed deliberately, inspect `key_matches`, fix or drop the
# named rows, and re-run -- do not widen the accepted matchTypes.
.key_label <- function(df) {
  out <- rep(NA_character_, nrow(df))
  for (.r in c("species", "genus", "family", "order", "class", "phylum", "kingdom")) {
    .hit <- names(df)[tolower(names(df)) == .r]
    if (!length(.hit)) next
    .v <- trimws(as.character(df[[.hit[1L]]]))
    .fill <- is.na(out) & !is.na(.v) & nzchar(.v)
    out[.fill] <- .v[.fill]
  }
  out
}
# An ALLOWLIST, not a list of known-bad values: GBIF's match API has added
# matchType values before (its v2 has others again), and a value we have never
# seen should stop the run rather than pass unexamined because nobody thought
# to name it. EXACT is the only value that means "this is the taxon you asked
# for".
.suspect <- !(key_matches$matchType %in% "EXACT")
.unresolved <- is.na(key_matches$usageKey)
if (any(.suspect | .unresolved)) {
  .bad <- which(.suspect | .unresolved)
  .labels <- .key_label(key_matches)
  stop(
    "GBIF key lookup: ", length(.bad), " of ", nrow(key_matches),
    " taxa did not resolve to a trustworthy GBIF key.\n",
    paste0("  ", .labels[.bad], " -- matchType ", key_matches$matchType[.bad],
           ", usageKey ", key_matches$usageKey[.bad], collapse = "\n"),
    "\nAn NA key is dropped silently by fetch_gbif_occurrences(); a FUZZY or ",
    "HIGHERRANK key fetches another taxon's records. Resolve or drop these ",
    "rows deliberately, then re-run.",
    call. = FALSE
  )
}
bbox_wkt <- TaxaFetch::make_bbox_wkt(
  lat = {{lat}}, lon = {{lon}},
  radius_deg = {{search_radius_deg}}
)
# GBIF_LIMIT WARNING. `limit` caps records PER TAXON KEY, and what survives is
# GBIF's own return order -- a non-random prefix, not a sample. Measured on real
# data: at limit = 10000, 45 of 231 Mugu taxa and 110 of 666 PtConception taxa
# sat exactly at the cap, and because each species' first 10,000 records came
# from the same few large multi-species surveys, every capped taxon emerged with
# an IDENTICAL spatial distribution (per-species median distance 104 km, IQR
# 104-104, against 81-217 for uncapped taxa). Both abundance and spatial pattern
# were then truncation artifacts. Prefer {{gbif_limit}} = NULL. Note this
# function has no on_cap guard -- TaxaFetch::get_gbif_occurrences() does, but it
# routes to the download API above 50 keys, which needs a GBIF account.
occurrences <- TaxaFetch::fetch_gbif_occurrences(
  keys       = keys,
  geometry   = bbox_wkt,
  year_range = {{year_range}},
  limit      = {{gbif_limit}},
  # Project-local cache, beside the checkpoints it feeds, rather than the
  # hidden tools::R_user_dir("TaxaFetch", "cache") default. GBIF zips are the
  # largest artefact this ecosystem produces -- 23 GB and 17 GB incidents,
  # 38 zips at 17.0 GB against 52 MB for every other cache file combined --
  # and being invisible from the project is why they went unnoticed.
  cache_dir  = {{gbif_cache_dir}}
)
occurrences <- TaxaFetch::filter_gbif_quality(occurrences)
occurrences <- TaxaFetch::dedupe_occurrences(occurrences)
message("Fetched ", nrow(occurrences), " occurrence records")
occurrences
