# ==============================================================================
# taxaflag_clear_cache.R
# TaxaFlag's wrapper over the shared TaxaTools cache engine, matching
# TaxaFetch::taxafetch_clear_cache() / TaxaLikely::taxalikely_clear_cache().
#
# TWO caches share this one management function, both one small .rds per
# key, named by a hash of the full key -- exactly the file-per-key shape
# TaxaTools::list_cache_files() is built for, so both are reported and
# pruned the same way as every other cache in the ecosystem rather than
# accumulating unmanaged:
#   1. review_assignments(cache_dir=)'s per-reviewed-taxon LLM verdict cache
#      (files ending "_review.rds").
#   2. check_gbif_tile_range(cache_dir=)'s per-(taxon, location, zoom, ...)
#      GBIF density-tile verdict cache (files ending "_tile_range.rds").
# ==============================================================================

.taxaflag_cache_patterns <- c("_review\\.rds$", "_tile_range\\.rds$")

#' Report and clear TaxaFlag's on-disk caches
#'
#' Lists, and optionally deletes, the per-key files written by
#' [review_assignments()] and [check_gbif_tile_range()] when either is given
#' a `cache_dir`: [review_assignments()]'s per-reviewed-taxon LLM verdict
#' cache, and [check_gbif_tile_range()]'s per-(taxon, location, zoom, ...)
#' GBIF density-tile verdict cache. Entries in both have no built-in expiry
#' -- a verdict stays valid until its own key changes (e.g. the taxon's
#' review context changes, or the query location/zoom changes), which makes
#' it a miss anyway -- so pruning is about disk usage and about deliberately
#' forcing a fresh review/re-fetch, not about correctness.
#'
#' @param cache_dir Character. The directory passed to
#'   [review_assignments()]'s or [check_gbif_tile_range()]'s `cache_dir`
#'   (each function's cache lives in its own directory, so point this at
#'   whichever one you want to inspect/clear). Defaults to
#'   `tools::R_user_dir("TaxaFlag", "cache")`, matching the sibling packages;
#'   workflows that pass a project-local directory should pass the same one
#'   here.
#' @param older_than_days Optional numeric. Delete only entries older than
#'   this many days. `NULL` (default) considers every entry.
#' @param dry_run Logical. `TRUE` reports what would be deleted without
#'   deleting it.
#' @param force Logical (default `FALSE`). Pass `TRUE` to clear a
#'   `cache_dir` that holds file(s) matching none of the recognized cache
#'   patterns -- see `TaxaTools::list_cache_files()`.
#' @return Invisibly, the inventory data frame
#'   ([TaxaTools::list_cache_files()] output) of the files considered.
#' @seealso [review_assignments()], [check_gbif_tile_range()],
#'   [TaxaTools::report_and_clear_cache()],
#'   `TaxaFetch::taxafetch_clear_cache()`, `TaxaLikely::taxalikely_clear_cache()`
#' @export
#' @examples
#' \dontrun{
#' taxaflag_clear_cache(dry_run = TRUE) # report only
#' taxaflag_clear_cache(older_than_days = 90) # prune old entries
#' }
taxaflag_clear_cache <- function(cache_dir = tools::R_user_dir("TaxaFlag", "cache"),
                                 older_than_days = NULL,
                                 dry_run = FALSE,
                                 force = FALSE) {
  inv <- TaxaTools::list_cache_files(cache_dir, .taxaflag_cache_patterns, force = force)
  TaxaTools::report_and_clear_cache(
    inv,
    label = "taxaflag_clear_cache", cache_dir = cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}

# ------------------------------------------------------------------------------
# Internal cache helpers for review_assignments(cache_dir=)
# ------------------------------------------------------------------------------

#' Filename hash for a review cache key
#'
#' Deliberately NOT relied on for correctness: the full key is stored inside
#' the file and checked on read (see .review_cache_read), so a collision costs
#' one re-asked taxon rather than returning another taxon's verdict. Base R
#' only, no new dependency.
#' @noRd
.review_cache_hash <- function(x) {
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

#' Read one cached review row, verifying its full key
#' @noRd
.review_cache_read <- function(path, key) {
  if (!file.exists(path)) {
    return(NULL)
  }
  ent <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(ent) || !is.list(ent) || is.null(ent$key) || is.null(ent$row)) {
    return(NULL)
  }
  if (!identical(ent$key, key)) {
    return(NULL)
  } # collision or stale layout
  if (!is.data.frame(ent$row) || nrow(ent$row) != 1L) {
    return(NULL)
  }
  ent$row
}

#' Write one review row to the cache, alongside its full key
#' @noRd
.review_cache_write <- function(path, key, row) {
  tryCatch(saveRDS(list(key = key, row = row), path),
    error = function(e) invisible(NULL)
  )
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# .review_cache_write_rows(): persist one batch's answered verdicts
#
# Called as soon as a batch returns, not after the whole marker, so answers
# already paid for survive a stop part-way through. `taxa_info` carries the
# cache bookkeeping: `cache_paths` and `cache_keys` are indexed by its rows, so
# a verdict is mapped back to its own key by taxon name.
#
# An unreviewed row is NEVER cached: caching a non-answer makes the omission
# permanent, because every later run is then a cache HIT on a row of NAs and
# the re-ask never gets a chance to fire. `unreviewed` is this batch's own
# missing labels, so the rule holds per batch exactly as it did per marker.
#' @noRd
.review_cache_write_rows <- function(rows, taxa_info, cache_paths, cache_keys,
                                     unreviewed = NULL) {
  if (is.null(cache_paths) || is.null(cache_keys)) {
    return(invisible(NULL))
  }
  if (is.null(rows) || !is.data.frame(rows) || nrow(rows) == 0L) {
    return(invisible(NULL))
  }
  unreviewed <- as.character(unreviewed %||% character(0))
  pos <- match(rows$taxon_name, taxa_info$taxon_name)
  for (k in which(!is.na(pos))) {
    if (rows$taxon_name[k] %in% unreviewed) next
    .review_cache_write(
      cache_paths[pos[k]], cache_keys[pos[k]],
      rows[k, , drop = FALSE]
    )
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# .review_reviewer_id(): who answered, as a component of an LLM cache key
#
# An LLM review is a JUDGEMENT, so two models can answer the same question
# differently. A key built only from the question serves one model's verdict to
# a call asking another, silently: the same defect class as a cache keyed on a
# name that does not encode the question, which this project has now hit
# several times. The reviewer belongs in the key.
#
# What is knowable without a network call and without reaching into another
# package's internals:
#   - options("TaxaID.provider"), which is the option call_api() itself reads
#     to choose a provider;
#   - the identity of llm_fn. For a function that lives in a package, its
#     signature (argument names AND defaults) is the stable identity: the four
#     TaxaTools entry points differ from each other in their defaults, and a
#     refactor of a function's body does not change it, so an unrelated edit
#     does not orphan a large verdict cache. For a caller's own wrapper, any
#     model it pins lives in the body, so the body is the identity.
#
# Neither catches two models from ONE provider, switched through set_model() or
# a pinned tier. That case is what model_label is for, and it is documented on
# both callers.
#
# Deparsing a signature is safe to store: an api_key default deparses to the
# Sys.getenv() CALL, never to a key value.
#
# The failure direction is deliberate. A component that changes when it did not
# need to costs one re-ask; a component that fails to change when it should
# returns the wrong model's verdict as if it were this one's.
.review_reviewer_id <- function(llm_fn, model_label = NULL, caching = FALSE) {
  if (!is.null(model_label)) {
    if (!is.character(model_label) || length(model_label) != 1L ||
      is.na(model_label)) {
      stop("'model_label' must be a single non-NA character string, or NULL.",
        call. = FALSE
      )
    }
    return(model_label)
  }
  provider <- getOption("TaxaID.provider")
  if (!is.character(provider) || length(provider) != 1L || is.na(provider)) {
    provider <- ""
  }
  env_name <- tryCatch(environmentName(environment(llm_fn)),
    error = function(e) ""
  )
  # A function that belongs to a loaded namespace identifies itself: its name
  # and formals are a stable description of what it will call. Anything else is
  # a closure the caller wrote, and all we can see of it is its SOURCE -- which
  # is exactly the hole this guard closes.
  from_namespace <- is.function(llm_fn) && nzchar(env_name) &&
    env_name %in% loadedNamespaces()
  if (!from_namespace) {
    if (isTRUE(caching)) {
      stop(
        "The model this llm_fn will call cannot be identified, so a cached ",
        "verdict from a DIFFERENT model could be served as a hit. A wrapper ",
        "written as function(p, ...) call_api(p, model = MODEL, ...) deparses ",
        "to the variable name \"MODEL\", not to the model it holds, so ",
        "changing MODEL would silently reuse the first model's answers. Pass ",
        "model_label = the resolved model string (for example ",
        "model_label = \"claude-opus-5-5\"), or set cache_dir = NULL to run ",
        "uncached.",
        call. = FALSE
      )
    }
    return(paste(provider, .review_cache_hash(paste(
      tryCatch(deparse(llm_fn), error = function(e) ""),
      collapse = "\n"
    )), sep = "/"))
  }
  if (isTRUE(caching)) {
    # The namespace path names the function, not the model it resolves: a
    # provider's "mid" tier can be re-pointed at a different model without the
    # key moving. Narrower than the wrapper hole above, and the provider is in
    # the key, so this warns rather than refusing -- but it is the same class
    # of staleness, and model_label closes it.
    warning(
      "The cache key records which FUNCTION answered, not which model it ",
      "resolved to: if this provider's tier is later pointed at another ",
      "model, cached verdicts from the first one will still be served. Pass ",
      "model_label = the resolved model string to key the model itself.",
      call. = FALSE
    )
  }
  paste(provider, paste(env_name, paste(deparse(args(llm_fn)), collapse = " "),
    sep = ":"
  ), sep = "/")
}
