# ==============================================================================
# build_habitat_lookup.R
# Cached, one-call wrapper over the three-step habitat LLM workflow
# (build_habitat_prompt() -> TaxaTools::prompt_api() -> parse_hierarchical_
# habitat_response()), plus taxahabitat_clear_cache(), TaxaHabitat's wrapper
# over the shared TaxaTools cache engine (matching TaxaFlag::taxaflag_clear_
# cache() and the other sibling packages).
#
# WHY: every production workflow re-asks the LLM for every taxon's habitat
# on every run, with no cache. A verdict that flips between runs (e.g. a
# river fish labelled Lotic one day and Lentic the next) moves that species'
# occurrence records in or out of a habitat-stratified site, which moves its
# kernel prior by orders of magnitude, which moves the consensus call -- so
# without caching, the published taxon list is not reproducible across
# identical re-runs. A full GreatLakes run without this cache lost 0.05 of
# Lamar precision to exactly this. TaxaFlag::review_assignments() has the
# same problem and the same fix (its cache_dir=); this mirrors that design:
# one small .rds per taxon, named by a hash of the FULL key, the full key
# verified on read so a hash collision is a miss, never a wrong verdict.
# ==============================================================================

.taxahabitat_cache_patterns <- c("_habitat\\.rds$")

#' Build a per-taxon habitat lookup with an on-disk cache
#'
#' One call that does what the three-step pattern
#' [build_habitat_prompt()] -> `TaxaTools::prompt_api()` ->
#' [parse_hierarchical_habitat_response()] does, but only asks the LLM about
#' taxa it has not already classified under the same scheme. The result is
#' the `habitats_df` that [assign_habitat_biological()] consumes.
#'
#' @section Why cache this at all:
#' A habitat verdict decides which occurrence records count toward a
#' habitat-stratified site prior in TaxaExpect. If the LLM answers
#' differently on two runs, a species can move from "locally observed" to
#' "locally undetected" (or back) with no change in the data, and every
#' downstream call that species competes in moves with it. Caching makes an
#' identical re-run reproduce the same priors, and makes the habitat step
#' free after the first run. Nothing here changes what the LLM is asked or
#' how its answer is parsed.
#'
#' @section What the cache key covers:
#' The taxon name, the habitat columns the scheme asks for (derived exactly
#' as [build_habitat_prompt()] derives them, so a changed scheme is a miss),
#' `extra_covariates`, `geographic_context`, and `cache_tag`. The LLM
#' function itself cannot be hashed -- if you change providers or models and
#' want fresh verdicts, pass a new `cache_tag` (e.g. the model name) or
#' clear the directory with [taxahabitat_clear_cache()].
#'
#' @section What is and is not cached:
#' Only a taxon whose parsed row carries a resolved `Habitat` (at least one
#' non-zero weight) is written. A taxon the LLM skipped, or that sat in a
#' failed chunk, comes back with `Habitat = NA` and is NOT cached, so it is
#' re-asked on the next run instead of being frozen as unknown.
#'
#' @param taxon_list Character vector of taxon names.
#' @param habitat_scheme Passed to [build_habitat_prompt()]: `NULL` (the
#'   three-realm default), `"IUCN_L1"`, or a scheme data frame.
#' @param llm_fn Passed to `TaxaTools::prompt_api()`. Defaults to the
#'   `TaxaID.llm_fn` option, else `TaxaTools::call_api`.
#' @param cache_dir Character or `NULL` (default). Directory for the
#'   per-taxon cache. `NULL` disables caching entirely (identical to the
#'   uncached three-step pattern). Workflows should pass a project-local
#'   directory, e.g. `file.path(OUT_DIR, paste0(OUT_PREFIX, "_habitat_cache"))`.
#' @param extra_covariates,chunk_size,geographic_context Passed to
#'   [build_habitat_prompt()].
#' @param cache_tag Character (default `""`). Free-text component of the
#'   cache key; change it to force fresh verdicts (e.g. after a model change).
#' @param pause_seconds,verbose Passed to `TaxaTools::prompt_api()`.
#' @return A data frame with one row per unique taxon in `taxon_list`
#'   (the same shape [parse_hierarchical_habitat_response()] returns), in
#'   `taxon_list` order, with a `cache_summary` attribute:
#'   `n_total`, `n_from_cache`, `n_called`, `n_cached_new`.
#' @seealso [build_habitat_prompt()], [parse_hierarchical_habitat_response()],
#'   [assign_habitat_biological()], [taxahabitat_clear_cache()]
#' @export
#' @examples
#' \dontrun{
#' scheme <- data.frame(l1_name = c("Lentic", "Lotic"), stringsAsFactors = FALSE)
#' habitat_lookup <- build_habitat_lookup(
#'   unique(occurrences$taxon_name),
#'   habitat_scheme = scheme,
#'   llm_fn = function(p, ...) TaxaTools::call_anthropic_api(p),
#'   cache_dir = file.path(OUT_DIR, paste0(OUT_PREFIX, "_habitat_cache"))
#' )
#' attr(habitat_lookup, "cache_summary")
#' }
build_habitat_lookup <- function(taxon_list,
                                 habitat_scheme = NULL,
                                 llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                                 cache_dir = NULL,
                                 extra_covariates = character(0),
                                 chunk_size = 60L,
                                 geographic_context = NULL,
                                 cache_tag = "",
                                 pause_seconds = 1,
                                 verbose = TRUE) {
  if (!is.character(taxon_list) || length(taxon_list) == 0L) {
    stop("build_habitat_lookup: 'taxon_list' must be a non-empty character vector.")
  }
  if (!is.null(cache_dir) &&
    (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir))) {
    stop("build_habitat_lookup: 'cache_dir' must be a single non-NA character string, or NULL.")
  }
  if (!is.character(cache_tag) || length(cache_tag) != 1L || is.na(cache_tag)) {
    stop("build_habitat_lookup: 'cache_tag' must be a single non-NA character string.")
  }

  taxon_list <- trimws(taxon_list[!is.na(taxon_list)])
  taxon_list <- unique(taxon_list[nzchar(taxon_list)])
  if (length(taxon_list) == 0L) {
    stop("build_habitat_lookup: 'taxon_list' has no non-empty names.")
  }

  # The scheme signature is the exact habitat column set build_habitat_prompt()
  # will ask for, derived by build_habitat_prompt() itself (cheap, no network)
  # so the key can never drift from what the prompt actually says.
  probe <- suppressMessages(build_habitat_prompt(
    taxon_list[1L],
    extra_covariates = extra_covariates,
    chunk_size = chunk_size,
    habitat_scheme = habitat_scheme,
    geographic_context = geographic_context
  ))
  shared_key <- paste(c(
    "v1", cache_tag,
    paste(probe$habitat_cols, collapse = "|"),
    paste(sort(extra_covariates), collapse = "|"),
    geographic_context %||% ""
  ), collapse = "")

  cache_hits <- NULL
  to_call <- taxon_list
  cache_keys <- NULL
  cache_paths <- NULL
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    }
    cache_keys <- paste(shared_key, taxon_list, sep = "")
    cache_paths <- file.path(
      cache_dir,
      paste0(vapply(cache_keys, .habitat_cache_hash, character(1)), "_habitat.rds")
    )
    hit_list <- list()
    hit_idx <- integer(0)
    for (i in seq_along(cache_paths)) {
      ent <- .habitat_cache_read(cache_paths[i], cache_keys[i])
      if (!is.null(ent)) {
        hit_idx <- c(hit_idx, i)
        hit_list[[length(hit_list) + 1L]] <- ent
      }
    }
    if (length(hit_idx) > 0L) {
      cache_hits <- dplyr::bind_rows(hit_list)
      to_call <- taxon_list[-hit_idx]
    }
    if (verbose) {
      message(sprintf(
        "build_habitat_lookup: cache: %d of %d taxa already classified; %d to call.",
        length(hit_idx), length(taxon_list), length(to_call)
      ))
    }
  }

  parsed <- NULL
  n_cached_new <- 0L
  if (length(to_call) > 0L) {
    prompt <- build_habitat_prompt(
      to_call,
      extra_covariates = extra_covariates,
      chunk_size = chunk_size,
      habitat_scheme = habitat_scheme,
      geographic_context = geographic_context
    )
    raw <- TaxaTools::prompt_api(
      prompt,
      llm_fn = llm_fn, pause_seconds = pause_seconds, verbose = verbose
    )
    if (is.character(raw) && length(raw) == 1L && !is.na(raw) && nzchar(trimws(raw))) {
      parsed <- parse_hierarchical_habitat_response(
        raw,
        taxon_list = prompt$taxa,
        habitat_scheme = prompt,
        extra_covariates = if (length(extra_covariates) > 0L) extra_covariates else NULL
      )
    } else {
      warning(
        "build_habitat_lookup: the LLM returned nothing usable; no taxa classified this call.",
        call. = FALSE
      )
    }

    if (!is.null(cache_dir) && !is.null(parsed) && nrow(parsed) > 0L) {
      resolved <- !is.na(parsed[["Habitat"]])
      pos <- match(parsed$taxon_name, taxon_list)
      for (k in which(resolved & !is.na(pos))) {
        .habitat_cache_write(
          cache_paths[pos[k]], cache_keys[pos[k]],
          parsed[k, , drop = FALSE]
        )
        n_cached_new <- n_cached_new + 1L
      }
    }
  }

  out <- dplyr::bind_rows(cache_hits, parsed)
  if (is.null(out) || nrow(out) == 0L) {
    out <- data.frame(taxon_name = character(0), stringsAsFactors = FALSE)
  } else {
    out <- out[order(match(out$taxon_name, taxon_list)), , drop = FALSE]
    rownames(out) <- NULL
    # habitat_breadth is DERIVED from the weight columns, never stored, so it is
    # recomputed here for every row rather than read back. Entries cached before
    # the column existed carry the weights but not the breadth, and bind_rows()
    # would fill those with NA -- silently, and permanently for any taxon whose
    # verdict is already cached. Deriving it instead means no cache-key bump and
    # no re-running the LLM over thousands of already-settled taxa.
    out[["habitat_breadth"]] <- .compute_habitat_breadth(out, probe$habitat_cols)
    # Declare the weight columns (see parse_hierarchical_habitat_response()).
    # bind_rows() drops attributes, so this is set after the combine, not
    # inherited from either input.
    attr(out, "habitat_cols") <- c(
      probe$habitat_cols,
      if ("Other_weight" %in% names(out)) "Other_weight"
    )
  }
  attr(out, "cache_summary") <- list(
    n_total = length(taxon_list),
    n_from_cache = if (is.null(cache_hits)) 0L else nrow(cache_hits),
    n_called = length(to_call),
    n_cached_new = n_cached_new
  )
  out
}

#' Report and clear TaxaHabitat's on-disk habitat-verdict cache
#'
#' Lists, and optionally deletes, the per-taxon files written by
#' [build_habitat_lookup()] when it is given a `cache_dir`. Entries have no
#' built-in expiry -- a verdict stays valid until the scheme, covariates,
#' context, or `cache_tag` change, which changes its key and makes it a miss
#' anyway -- so pruning is about disk usage and about deliberately forcing a
#' fresh classification, not about correctness.
#'
#' @param cache_dir Character. The directory passed to
#'   [build_habitat_lookup()]'s `cache_dir`. Defaults to
#'   `tools::R_user_dir("TaxaHabitat", "cache")`, matching the sibling
#'   packages; workflows that pass a project-local directory should pass the
#'   same one here.
#' @param older_than_days Optional numeric. Delete only entries older than
#'   this many days. `NULL` (default) considers every entry.
#' @param dry_run Logical. `TRUE` reports what would be deleted without
#'   deleting it.
#' @return Invisibly, the inventory data frame
#'   (`TaxaTools::list_cache_files()` output) of the files considered.
#' @seealso [build_habitat_lookup()], `TaxaTools::report_and_clear_cache()`,
#'   `TaxaFlag::taxaflag_clear_cache()`
#' @export
#' @examples
#' \dontrun{
#' taxahabitat_clear_cache(dry_run = TRUE)
#' }
taxahabitat_clear_cache <- function(cache_dir = tools::R_user_dir("TaxaHabitat", "cache"),
                                    older_than_days = NULL,
                                    dry_run = FALSE) {
  inv <- TaxaTools::list_cache_files(cache_dir, .taxahabitat_cache_patterns)
  TaxaTools::report_and_clear_cache(
    inv,
    label = "taxahabitat_clear_cache", cache_dir = cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}

# ------------------------------------------------------------------------------
# Internal cache helpers (same shape as TaxaFlag's review cache)
# ------------------------------------------------------------------------------

#' Filename hash for a habitat cache key. Not relied on for correctness: the
#' full key is stored inside the file and checked on read.
#' @noRd
.habitat_cache_hash <- function(x) {
  ints <- utf8ToInt(x)
  n <- length(ints)
  if (n == 0L) {
    return("empty-0-0")
  }
  v <- as.numeric(ints)
  a <- sum(v * seq_len(n)) %% 2147483647
  b <- sum(v * rev(seq_len(n))) %% 1000000007
  sprintf("%010.0f-%010.0f-%06d", a, b, n)
}

#' @noRd
.habitat_cache_read <- function(path, key) {
  if (!file.exists(path)) {
    return(NULL)
  }
  ent <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(ent) || !is.list(ent) || is.null(ent$key) || is.null(ent$row)) {
    return(NULL)
  }
  if (!identical(ent$key, key)) {
    return(NULL)
  }
  if (!is.data.frame(ent$row) || nrow(ent$row) != 1L) {
    return(NULL)
  }
  ent$row
}

#' @noRd
.habitat_cache_write <- function(path, key, row) {
  tryCatch(saveRDS(list(key = key, row = row), path),
    error = function(e) invisible(NULL)
  )
  invisible(NULL)
}
