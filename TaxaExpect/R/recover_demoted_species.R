#' Recover Species Demoted to Genus by GlobalNames
#'
#' When \code{verify_taxon_names(backbone_id = 4)} resolves a species binomial
#' to genus only (a known GlobalNames/NCBI index gap), this helper queries
#' NCBI taxonomy directly via \code{rentrez} to recover the species-level name
#' and fill in the \code{species} column of the lookup table.
#'
#' @param lookup Data frame output of \code{change_backbone()}, with columns
#'   \code{gbif_name} (original GBIF names) and rank columns from the
#'   translated backbone.
#' @param backbone_id Integer. The target backbone ID. Recovery is only
#'   attempted for NCBI (backbone_id = 4).
#' @param rank_system Character vector of rank names (coarse to fine).
#' @param verbose Logical. Print recovery messages.
#' @return The lookup data frame with species column filled where recovery
#'   succeeded.
#' @noRd
.recover_demoted_species <- function(lookup, backbone_id, rank_system,
                                      verbose = FALSE) {

  # Only attempt recovery for NCBI backbone
  if (!identical(as.integer(backbone_id), 4L)) return(lookup)
  if (!"species" %in% names(lookup)) return(lookup)
  if (!"gbif_name" %in% names(lookup)) return(lookup)

  # Identify binomials that were demoted: input has a space (binomial) but
  # species column is NA in the output
  is_binomial <- grepl(" ", lookup$gbif_name) & !grepl("\\s\u00d7\\s", lookup$gbif_name)
  is_demoted  <- is_binomial & (is.na(lookup$species) | !nzchar(lookup$species))

  if (sum(is_demoted) == 0L) return(lookup)

  if (!requireNamespace("rentrez", quietly = TRUE)) {
    warning(
      "build_priors: ", sum(is_demoted), " species lost to genus during backbone ",
      "translation. Install 'rentrez' to enable direct NCBI taxonomy recovery.",
      call. = FALSE
    )
    return(lookup)
  }

  demoted_names <- unique(lookup$gbif_name[is_demoted])
  msg <- if (verbose) message else function(...) invisible(NULL)
  msg(sprintf(
    "  Recovering %d species demoted to genus by GlobalNames (direct NCBI lookup)...",
    length(demoted_names)
  ))

  # Query NCBI taxonomy for each demoted species
  recovery_map <- data.frame(
    gbif_name    = demoted_names,
    ncbi_species = NA_character_,
    stringsAsFactors = FALSE
  )

  delay <- if (nzchar(Sys.getenv("ENTREZ_KEY", ""))) 0.11 else 0.34

  for (i in seq_along(demoted_names)) {
    sp <- demoted_names[i]
    tryCatch({
      res <- rentrez::entrez_search(
        db = "taxonomy",
        term = paste0(sp, "[Scientific Name]"),
        retmax = 1L
      )
      if (as.integer(res$count) > 0L) {
        recovery_map$ncbi_species[i] <- sp
      }
    }, error = function(e) {
      # Silently skip failed lookups
    })
    if (i < length(demoted_names)) Sys.sleep(delay)
  }

  n_recovered <- sum(!is.na(recovery_map$ncbi_species))
  if (n_recovered == 0L) {
    msg("  No species recovered from NCBI taxonomy.")
    return(lookup)
  }

  msg(sprintf("  Recovered %d of %d demoted species from NCBI taxonomy.",
              n_recovered, length(demoted_names)))

  # Fill species column in lookup for recovered names
  recovered <- recovery_map[!is.na(recovery_map$ncbi_species), ]
  for (j in seq_len(nrow(recovered))) {
    mask <- lookup$gbif_name == recovered$gbif_name[j] & is_demoted
    lookup$species[mask] <- recovered$ncbi_species[j]

    # Also update target_name if it exists (it's the translated matched_name)
    if ("target_name" %in% names(lookup)) {
      lookup$target_name[mask] <- recovered$ncbi_species[j]
    }
  }

  if (verbose) {
    failed <- recovery_map$gbif_name[is.na(recovery_map$ncbi_species)]
    if (length(failed) > 0L) {
      msg(sprintf("  Not found in NCBI: %s", paste(failed, collapse = ", ")))
    }
  }

  lookup
}
