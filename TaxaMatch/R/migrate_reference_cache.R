# ==============================================================================
# migrate_reference_cache() -- carry an existing evaluate_reference_accessions()
# cache across a params_key / cache-version change without re-BLASTing the
# rows whose verdict the change cannot withdraw.
# ==============================================================================

#' Migrate a Reference-Accession Cache to a New params_key
#'
#' [evaluate_reference_accessions()] stamps every cached row with one global
#' `params_key` (its verdict-affecting arguments plus an internal cache
#' version). Bumping that version -- as the 2026-09-03 switch to the
#' primer-stripped `query_span = "amplicon"` did (`"v5_amplicon_query"`) --
#' invalidates every existing row: ~3,000 real ones (PtConception 995;
#' GreatLakes 1060 + 280 + 690). This helper rewrites the key on the rows the
#' change cannot have altered, so only the rest re-BLAST.
#'
#' @section Why only `"congruent"` rows are carried forward:
#' `"congruent"` asserts that corroborating evidence WAS found. Stripping the
#' primers from the query only ADDS short amplicon-only deposits to what the
#' hit list can contain; it cannot withdraw a match that was already
#' observed, so a `"congruent"` verdict under the old query is still
#' `"congruent"` under the new one. Every other flag (`"incongruent"`,
#' `"insufficient_independent_evidence"`, `"not_evaluated_oversized"`,
#' `"not_evaluated_wrong_marker"`) is a
#' statement about absence or about not knowing -- exactly what the new query
#' can overturn -- so those rows are left under the old key and re-evaluate on
#' the next call. That is the cheap part (PtConception: 76 rows; GreatLakes:
#' ~123), and it is where every actionable verdict lives.
#'
#' The sidecar `reference_pair_cache.rds` (per-partner votes) is migrated for
#' the same accessions, so [refine_reference_verdicts()] keeps their votes
#' and a later re-evaluation replaces rather than duplicates them.
#'
#' @section Backup:
#' The cache file is copied to
#' `reference_accession_cache.rds.bak_pre_<to-version>` (and the pair cache to
#' `reference_pair_cache.rds.bak_pre_<to-version>`) before anything is
#' rewritten, following the 2026-08-11/13 `.bak_pre_*` convention. An
#' existing backup of that name is never overwritten -- it holds the earliest
#' pre-migration state, which is the one worth keeping.
#'
#' @param cache_dir Character. The directory holding
#'   `reference_accession_cache.rds`.
#' @param to_key Character or `NULL` (default). The `params_key` to migrate
#'   to. `NULL` uses the key [evaluate_reference_accessions()]'s own current
#'   defaults produce (built by the same internal code the function uses).
#'   If you screen with non-default verdict-affecting arguments (`top_n`,
#'   `max_hits`, ...), pass the key your call produces -- read it off
#'   `params_key` in a row that call has written.
#' @param from_key Character vector or `NULL` (default). Which existing keys
#'   to migrate from. `NULL` means every key other than `to_key`.
#' @param verbose Logical (default `TRUE`). Print the counts.
#'
#' @return Invisibly, a list: `to_key`, `n_carried_forward` (rows rewritten),
#'   `n_left_to_reevaluate` (rows under `from_key` NOT rewritten, by flag in
#'   `left_by_flag`), `n_already_current`, `backup_path`.
#'
#' @seealso [evaluate_reference_accessions()]
#'
#' @examples
#' \dontrun{
#' migrate_reference_cache("ptcon_ref_eval_cache")
#' }
#'
#' @export
migrate_reference_cache <- function(cache_dir, to_key = NULL, from_key = NULL,
                                    verbose = TRUE) {
  if (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir) ||
      !dir.exists(cache_dir))
    stop("cache_dir must be an existing directory.", call. = FALSE)
  if (is.null(to_key)) to_key <- .default_params_key()
  if (!is.character(to_key) || length(to_key) != 1L || is.na(to_key) || !nzchar(to_key))
    stop("to_key must be NULL or a single non-empty string.", call. = FALSE)
  if (!is.null(from_key) && (!is.character(from_key) || length(from_key) == 0L))
    stop("from_key must be NULL or a character vector of params_key values.", call. = FALSE)

  path <- file.path(cache_dir, "reference_accession_cache.rds")
  if (!file.exists(path))
    stop(sprintf("No reference_accession_cache.rds in %s -- nothing to migrate.", cache_dir),
         call. = FALSE)
  cache <- readRDS(path)
  if (!is.data.frame(cache) || !all(c("accession", "hierarchy_flag", "params_key") %in% names(cache)))
    stop("The cache file is not an evaluate_reference_accessions() cache (needs accession, hierarchy_flag, params_key).",
         call. = FALSE)

  to_version <- sub("^.*[|]", "", to_key)
  backup_suffix <- paste0(".bak_pre_", to_version)
  backup_path <- paste0(path, backup_suffix)
  if (!file.exists(backup_path)) {
    file.copy(path, backup_path, overwrite = FALSE)
  } else if (verbose) {
    message(sprintf("migrate_reference_cache(): backup %s already exists -- not overwritten.",
                    basename(backup_path)))
  }

  is_from <- if (is.null(from_key)) {
    !is.na(cache$params_key) & cache$params_key != to_key
  } else {
    !is.na(cache$params_key) & cache$params_key %in% from_key
  }
  carry <- is_from & cache$hierarchy_flag %in% "congruent"

  if (!"migrated_from" %in% names(cache)) cache$migrated_from <- NA_character_
  cache$migrated_from[carry] <- cache$params_key[carry]
  cache$params_key[carry] <- to_key
  saveRDS(cache, path)

  left <- is_from & !carry
  left_by_flag <- if (any(left)) table(cache$hierarchy_flag[left], useNA = "ifany") else table(character(0L))

  # Pair cache: same accessions, same rewrite, same backup convention.
  pair_path <- file.path(cache_dir, "reference_pair_cache.rds")
  n_pairs_carried <- 0L
  if (file.exists(pair_path)) {
    pairs <- tryCatch(readRDS(pair_path), error = function(e) NULL)
    if (is.data.frame(pairs) && all(c("id_x", "params_key") %in% names(pairs))) {
      pair_backup <- paste0(pair_path, backup_suffix)
      if (!file.exists(pair_backup)) file.copy(pair_path, pair_backup, overwrite = FALSE)
      pair_from <- if (is.null(from_key)) {
        !is.na(pairs$params_key) & pairs$params_key != to_key
      } else {
        !is.na(pairs$params_key) & pairs$params_key %in% from_key
      }
      pair_carry <- pair_from & pairs$id_x %in% cache$accession[carry]
      pairs$params_key[pair_carry] <- to_key
      saveRDS(pairs, pair_path)
      n_pairs_carried <- sum(pair_carry)
    }
  }

  n_current <- sum(!is.na(cache$params_key) & cache$params_key == to_key & !carry)
  if (verbose) {
    message(sprintf(
      "migrate_reference_cache(): %s\n  to_key: %s\n  %d 'congruent' row(s) carried forward to the new key (migrated_from stamped)\n  %d row(s) left under the old key to re-evaluate on the next call%s\n  %d row(s) were already current; %d pair-cache row(s) carried forward\n  backup: %s",
      path, to_key, sum(carry), sum(left),
      if (any(left)) paste0(" (", paste(sprintf("%s=%d", names(left_by_flag), as.integer(left_by_flag)),
                                        collapse = ", "), ")") else "",
      n_current, n_pairs_carried, backup_path
    ))
  }

  invisible(list(
    to_key = to_key,
    n_carried_forward = sum(carry),
    n_left_to_reevaluate = sum(left),
    left_by_flag = left_by_flag,
    n_already_current = n_current,
    n_pairs_carried_forward = n_pairs_carried,
    backup_path = backup_path
  ))
}
