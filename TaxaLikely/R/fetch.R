utils::globalVariables(c(
  "acc", "taxid", "slen", "title", "organism", "clean_header",
  "genus", "species"
))

# ==============================================================================
# MODULE A: REFERENCE SEQUENCE ACQUISITION
# ==============================================================================

# --- Internal helpers ---------------------------------------------------------

#' NCBI rate-limit delay: 0.34s without API key, 0.11s with key
#' @noRd
.ncbi_delay <- function() {
  has_key <- nzchar(Sys.getenv("ENTREZ_KEY", "")) ||
             nzchar(Sys.getenv("NCBI_API_KEY", ""))
  if (has_key) 0.11 else 0.34
}

#' Build an NCBI nucleotide search term
#' @noRd
.build_search_term <- function(taxon, barcode_term, min_date = NULL,
                               max_date = NULL) {

  # Barcode clause: OR multiple synonyms

  # Map common barcode terms to NCBI [GENE] field tags for precision.
  # Only protein-coding genes and specific loci that NCBI indexes under [GENE].
  gene_map <- c(
    "coi"  = "COI",   "co1"  = "COI",   "cox1" = "COI",
    "cytb" = "cytb",  "cob"  = "cytb",
    "its"  = "ITS",   "its2" = "ITS2",  "its1" = "ITS1",
    "rbcl" = "rbcL",  "matk" = "matK",
    "trnl" = "trnL"
  )

  # Map primer names to the underlying gene/locus they amplify.
  # When a primer name is not in gene_map, we search for both the primer name
  # AND the gene locus (OR'd together). This catches sequences annotated with
  # the gene name but not the primer name (e.g. Fundulidae has 12S sequences
  # but none tagged "MiFish").
  primer_to_locus <- c(
    "mifish"   = "12S",  "mifish-u" = "12S",  "mifishu"  = "12S",
    "mifish-e" = "12S",  "mifishe"  = "12S",
    "teleo"    = "12S",  "teleost"  = "12S",
    "leray"    = "COI",  "mlcoi"    = "COI",  "mlcoiintf" = "COI",
    "jgher"    = "COI",  "dgher"    = "COI",
    "fishr1"   = "16S",  "fishr2"   = "16S",
    "vert01"   = "12S",  "vert02"   = "16S"
  )

  bc_parts <- vapply(barcode_term, function(bt) {
    key <- tolower(trimws(bt))
    gene <- gene_map[key]
    if (!is.na(gene)) {
      # Known gene name: use [GENE] field directly
      paste0(gene, "[GENE]")
    } else {
      # Primer name or unrecognised term: search [All Fields]
      primer_clause <- paste0(bt, "[All Fields]")
      # Also OR in the underlying locus if known
      locus <- primer_to_locus[key]
      if (!is.na(locus)) {
        paste0("(", primer_clause, " OR ", locus, "[All Fields])")
      } else {
        primer_clause
      }
    }
  }, character(1L), USE.NAMES = FALSE)

  bc_clause <- if (length(bc_parts) == 1L) {
    bc_parts
  } else {
    paste0("(", paste(bc_parts, collapse = " OR "), ")")
  }

  term <- paste0(taxon, "[Organism] AND ", bc_clause)

  # Date clause (PDAT = publication date)

  if (!is.null(min_date) || !is.null(max_date)) {
    d_start <- if (!is.null(min_date)) min_date else "1900/01/01"
    d_end   <- if (!is.null(max_date)) max_date else "3000/12/31"
    term    <- paste0(term, " AND (", d_start, "[PDAT] : ", d_end, "[PDAT])")
  }

  term
}


#' Fetch NCBI summaries in batches (lightweight: accession, taxid, length)
#' @noRd
.fetch_summaries_batched <- function(search_obj, batch_size = 200L) {
  total  <- as.integer(search_obj$count)
  starts <- seq(0L, total - 1L, by = batch_size)
  res    <- vector("list", length(starts))

  for (i in seq_along(starts)) {
    attempt <- 0L
    success <- FALSE
    while (attempt < 3L && !success) {
      attempt <- attempt + 1L
      tryCatch({
        summ <- rentrez::entrez_summary(
          db          = "nucleotide",
          web_history = search_obj$web_history,
          retstart    = starts[i],
          retmax      = batch_size
        )
        # entrez_summary returns a single item or a list of items
        if (!is.null(summ$uid)) summ <- list(summ)

        res[[i]] <- do.call(rbind, lapply(summ, function(x) {
          data.frame(
            acc      = as.character(if (is.null(x$caption))  NA else x$caption),
            title    = as.character(if (is.null(x$title))    NA else x$title),
            taxid    = as.character(if (is.null(x$taxid))    NA else x$taxid),
            slen     = as.numeric(if (is.null(x$slen))       NA else x$slen),
            organism = as.character(if (is.null(x$organism)) NA else x$organism),
            stringsAsFactors = FALSE
          )
        }))
        success <- TRUE
      }, error = function(e) {
        if (attempt < 3L) Sys.sleep(attempt)
      })
    }
  }

  do.call(rbind, Filter(Negate(is.null), res))
}


#' Fetch full taxonomy lineage from NCBI taxonomy DB via taxids
#' @noRd
.fetch_taxonomy_map <- function(taxids, desired_ranks, batch_size = 100L) {
  batches <- split(taxids, ceiling(seq_along(taxids) / batch_size))
  res     <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    attempt <- 0L
    success <- FALSE
    while (attempt < 3L && !success) {
      attempt <- attempt + 1L
      tryCatch({
        xml_raw <- rentrez::entrez_fetch(
          db = "taxonomy", id = batches[[i]], rettype = "xml"
        )
        xml_doc <- xml2::read_xml(xml_raw)
        nodes   <- xml2::xml_find_all(xml_doc, "//TaxaSet/Taxon")

        parsed <- lapply(nodes, function(node) {
          this_id   <- xml2::xml_text(xml2::xml_find_first(node, "./TaxId"))
          this_sci  <- xml2::xml_text(xml2::xml_find_first(node, "./ScientificName"))
          this_rank <- xml2::xml_text(xml2::xml_find_first(node, "./Rank"))

          row <- stats::setNames(
            as.list(rep(NA_character_, length(desired_ranks))), desired_ranks
          )
          row$taxid <- this_id

          # Parse lineage
          lineage_nodes <- xml2::xml_find_all(node, "./LineageEx/Taxon")
          l_ranks <- xml2::xml_text(xml2::xml_find_first(lineage_nodes, "./Rank"))
          l_names <- xml2::xml_text(xml2::xml_find_first(lineage_nodes, "./ScientificName"))

          for (k in seq_along(l_ranks)) {
            if (l_ranks[k] %in% desired_ranks) row[[l_ranks[k]]] <- l_names[k]
          }

          # The node's own rank
          if (this_rank %in% desired_ranks) row[[this_rank]] <- this_sci

          as.data.frame(row, stringsAsFactors = FALSE)
        })

        res[[i]] <- do.call(rbind, parsed)
        success  <- TRUE
      }, error = function(e) {
        if (attempt < 3L) Sys.sleep(attempt)
      })
    }
    Sys.sleep(.ncbi_delay())
  }

  do.call(rbind, Filter(Negate(is.null), res))
}


#' Download FASTA sequences in batches
#' @noRd
.fetch_fasta_batched <- function(accessions, batch_size = 200L) {
  batches <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  chunks  <- vector("character", length(batches))

  for (i in seq_along(batches)) {
    attempt <- 0L
    success <- FALSE
    while (attempt < 3L && !success) {
      attempt <- attempt + 1L
      tryCatch({
        chunks[i] <- rentrez::entrez_fetch(
          db = "nucleotide", id = batches[[i]],
          rettype = "fasta", retmode = "text"
        )
        success <- TRUE
      }, error = function(e) {
        if (attempt < 3L) Sys.sleep(attempt)
      })
    }
    Sys.sleep(.ncbi_delay())
  }

  paste(chunks[nchar(chunks) > 0L], collapse = "\n")
}


#' Parse FASTA text into a data frame of composite_id + sequence
#' @noRd
.parse_fasta_text <- function(fasta_text) {
  lines      <- strsplit(fasta_text, "\n")[[1L]]
  header_idx <- which(startsWith(lines, ">"))

  if (length(header_idx) == 0L) return(data.frame(
    composite_id = character(0L), sequence = character(0L),
    stringsAsFactors = FALSE
  ))

  seq_end_idx <- c(header_idx[-1L] - 1L, length(lines))

  ids  <- character(length(header_idx))
  seqs <- character(length(header_idx))

  for (k in seq_along(header_idx)) {
    hdr    <- sub("^>", "", lines[header_idx[k]])
    # Accession = first token; strip version suffix (.1, .2, etc.)
    ids[k] <- sub("\\.[0-9]+$", "", strsplit(trimws(hdr), "\\s+")[[1L]][1L])
    seq_lines <- lines[(header_idx[k] + 1L):seq_end_idx[k]]
    seqs[k]   <- paste(seq_lines[nchar(seq_lines) > 0L], collapse = "")
  }

  data.frame(composite_id = ids, sequence = seqs, stringsAsFactors = FALSE)
}


# --- Exported functions -------------------------------------------------------

#' Fetch reference sequences from NCBI for model building
#'
#' Searches NCBI nucleotide by taxon name and barcode marker, retrieves full
#' taxonomy via the NCBI taxonomy database, filters by sequence length and
#' quality, optionally downsamples, and returns a `reference_df` ready for
#' [build_sequence_matrix()].
#'
#' The function performs a **count-first estimation** before downloading.
#' If the total exceeds `max_sequences`, sequences are subsampled
#' proportionally across taxa (each taxon gets at least `min_per_taxon`
#' sequences). This ensures all taxa are represented while staying within
#' the download budget.
#'
#' @section Why not use match object accessions:
#' The match object from TaxaMatch contains only sequences that happened to
#' match your queries -- a biased subset.
#' A good likelihood model needs the broader landscape: within-species
#' variation, between-species distances, and coverage of related taxa.
#' This function searches by **taxon + marker** to get that full picture.
#'
#' @section Caching and resumability:
#' For large searches (many taxa, slow NCBI responses), set `cache_dir` to
#' a directory path.
#' Completed per-taxon results are saved as `.rds` files.
#' If the function is interrupted, re-running with the same `cache_dir`
#' skips already-downloaded taxa.
#'
#' @param taxa Character vector of taxon names to search.
#'   Can be any rank: species, genus, family, order, or class
#'   (e.g., `"Fundulus"`, `"Gobiidae"`, `"Actinopterygii"`).
#'   Each taxon is searched separately; results are combined.
#' @param barcode_term Character scalar or vector of marker names
#'   (e.g., `"12S"`, `c("COI", "Co1", "Coxi")`).
#'   Multiple synonyms are OR-ed in the NCBI query.
#' @param rank_system Character vector of taxonomy ranks, **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`).
#'   These ranks are resolved from the NCBI taxonomy database.
#' @param min_len Integer or NULL.
#'   Minimum sequence length (bp).
#'   If NULL, auto-resolved from `barcode_term` using built-in defaults.
#' @param max_len Integer or NULL.
#'   Maximum sequence length (bp).
#'   If NULL, auto-resolved from `barcode_term`.
#'   Set both to NULL and supply wide manual values to cast a broader net
#'   (useful for exploring how sequence length relates to errors).
#' @param max_per_species Integer or NULL (default 5).
#'   Maximum sequences to retain per species (stratified downsampling).
#'   NULL disables species-level capping.
#' @param max_per_genus Integer or NULL (default NULL).
#'   Maximum sequences per genus after species-level capping.
#'   NULL disables genus-level capping.
#' @param priority_taxa Character vector or NULL (default NULL).
#'   Species names that should be fully represented in the reference.
#'   Typically the species from the user's match data. When total NCBI hits
#'   exceed `max_sequences`, priority species are searched individually and
#'   given full allocation; the remaining budget is split proportionally
#'   across the broader `taxa` (families/genera). This ensures the model has
#'   good within-species and between-species distances for species that
#'   actually appear in the query data.
#' @param max_sequences Integer (default 10000).
#'   Safety valve for total download volume.
#'   If the total NCBI hit count exceeds this, sequences are subsampled
#'   proportionally across taxa (each taxon gets at least
#'   `min_per_taxon` sequences). Priority taxa (if provided) are fetched
#'   first; the remaining budget is allocated to broader family searches.
#' @param min_per_taxon Integer (default 50).
#'   When subsampling due to `max_sequences`, each taxon is guaranteed
#'   at least this many sequences (or all of them if fewer exist).
#' @param blacklist_regex Character scalar.
#'   Regex pattern for filtering sequence titles.
#'   Sequences whose title matches this pattern are excluded.
#' @param min_date Character or NULL (e.g., `"2010/01/01"`).
#'   Earliest publication date for sequences.
#' @param max_date Character or NULL (e.g., `"2024/12/31"`).
#'   Latest publication date.
#' @param cache_dir Character path.
#'   Per-taxon intermediate results are cached here, enabling resumable
#'   downloads when NCBI rate-limits or the session is interrupted.
#'   Default \code{tempdir()} (clears on R restart). Set to a persistent
#'   path for cross-session caching, or \code{NULL} to disable.
#' @param ncbi_api_key Character or NULL.
#'   NCBI API key (increases rate limit from 3 to 10 requests/second).
#'   Can also be set via the `ENTREZ_KEY` environment variable.
#'
#' @return A data frame (`reference_df`) with columns:
#'   \describe{
#'     \item{`composite_id`}{NCBI accession (version suffix stripped).}
#'     \item{`sequence`}{DNA sequence string.}
#'     \item{rank columns}{One column per rank in `rank_system`
#'       (e.g., `family`, `genus`, `species`).}
#'   }
#'   Ready for input to [build_sequence_matrix()].
#'
#' @seealso [read_reference_fasta()] for loading a local FASTA file,
#'   [build_sequence_matrix()] for the next step
#'
#' @examples
#' \dontrun{
#' ref <- fetch_reference_sequences(
#'   taxa = c("Fundulus", "Atherinops"),
#'   barcode_term = "MiFishU",
#'   max_sequences = 500
#' )
#' head(ref)
#' }
#'
#' @importFrom dplyr filter mutate group_by slice_sample ungroup n select
#'   all_of left_join distinct
#' @export
fetch_reference_sequences <- function(taxa,
                                      barcode_term,
                                      rank_system     = c("family", "genus", "species"),
                                      min_len         = NULL,
                                      max_len         = NULL,
                                      max_per_species = NULL,
                                      max_per_genus   = NULL,
                                      priority_taxa   = NULL,
                                      max_sequences   = 10000L,
                                      min_per_taxon   = 50L,
                                      blacklist_regex = "uncultured|environmental|predicted|vector|synthetic|unverified",
                                      min_date        = NULL,
                                      max_date        = NULL,
                                      cache_dir       = tempdir(),
                                      ncbi_api_key    = NULL) {

  # --- Validate inputs --------------------------------------------------------
  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("fetch_reference_sequences requires the 'rentrez' package. Install with: install.packages('rentrez')")
  if (!requireNamespace("xml2", quietly = TRUE))
    stop("fetch_reference_sequences requires the 'xml2' package. Install with: install.packages('xml2')")
  if (!is.character(taxa) || length(taxa) == 0L)
    stop("taxa must be a non-empty character vector")
  if (!is.character(barcode_term) || length(barcode_term) == 0L)
    stop("barcode_term must be a non-empty character vector")
  if (!is.character(rank_system) || length(rank_system) == 0L)
    stop("rank_system must be a non-empty character vector (coarse to fine)")
  if (!is.null(max_per_species) && (!is.numeric(max_per_species) ||
      max_per_species < 1L))
    stop("max_per_species must be a positive integer or NULL")
  if (!is.null(max_per_genus) && (!is.numeric(max_per_genus) ||
      max_per_genus < 1L))
    stop("max_per_genus must be a positive integer or NULL")

  # Set NCBI API key if provided
  if (!is.null(ncbi_api_key)) {
    rentrez::set_entrez_key(ncbi_api_key)
  }

  delay <- .ncbi_delay()

  # Resolve length defaults from barcode_term
  len_bounds <- TaxaTools::resolve_barcode_lengths(barcode_term, min_len, max_len)
  eff_min_len <- len_bounds[1L]
  eff_max_len <- len_bounds[2L]

  # Set up cache directory
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  }

  # --- Step 1: Count-first estimation ----------------------------------------
  message("Estimating search size...")
  counts <- integer(length(taxa))
  names(counts) <- taxa

  for (i in seq_along(taxa)) {
    term <- .build_search_term(taxa[i], barcode_term, min_date, max_date)
    tryCatch({
      res <- rentrez::entrez_search(db = "nucleotide", term = term, retmax = 0L)
      counts[i] <- as.integer(res$count)
    }, error = function(e) {
      warning(sprintf("Count query failed for '%s': %s", taxa[i],
                      conditionMessage(e)))
      counts[i] <<- NA_integer_
    })
    Sys.sleep(delay)
  }

  n_failed_counts <- sum(is.na(counts))
  total <- sum(counts, na.rm = TRUE)
  message(sprintf("NCBI hit counts by taxon (%d total):", total))
  for (i in seq_along(taxa)) {
    message(sprintf("  %s: %s", taxa[i],
                    if (is.na(counts[i])) "error" else
                      format(counts[i], big.mark = ",")))
  }

  if (total == 0L && n_failed_counts == length(taxa)) {
    stop("All NCBI count queries failed. Check your internet connection and NCBI API key.")
  }

  if (total == 0L) {
    message("No sequences found. Check taxon names and barcode_term.")
    return(data.frame(
      composite_id = character(0L), sequence = character(0L),
      stringsAsFactors = FALSE
    ))
  }

  # --- Priority species + proportional subsampling when over budget --------
  # Two tiers: (1) priority species get full allocation, (2) remaining budget
  # split proportionally across broader taxa (families/genera).
  priority_counts <- integer(0L)
  priority_budget <- 0L

  if (total > max_sequences && !is.null(priority_taxa) &&
      length(priority_taxa) > 0L) {
    # Clean priority list: unique, non-empty species names
    priority_taxa <- unique(trimws(priority_taxa))
    priority_taxa <- priority_taxa[!is.na(priority_taxa) & nzchar(priority_taxa)]

    if (length(priority_taxa) > 0L) {
      message(sprintf(
        "\nTotal NCBI hits (%s) exceed max_sequences (%s).\n",
        format(total, big.mark = ","),
        format(max_sequences, big.mark = ",")))
      message(sprintf(
        "Counting %d priority species from match data...",
        length(priority_taxa)))

      # Count hits for each priority species
      priority_counts <- integer(length(priority_taxa))
      names(priority_counts) <- priority_taxa

      p_batches <- split(priority_taxa,
                         ceiling(seq_along(priority_taxa) / 40L))
      for (pb in p_batches) {
        for (sp in pb) {
          tryCatch({
            sp_term <- .build_search_term(sp, barcode_term, min_date, max_date)
            res <- rentrez::entrez_search(db = "nucleotide", term = sp_term,
                                          retmax = 0L)
            priority_counts[[sp]] <- as.integer(res$count)
          }, error = function(e) {
            priority_counts[[sp]] <<- 0L
          })
          Sys.sleep(delay)
        }
      }

      priority_budget <- sum(priority_counts, na.rm = TRUE)
      n_priority_spp <- sum(priority_counts > 0L)
      message(sprintf(
        "  Priority species: %d of %d have sequences (%s total hits)",
        n_priority_spp, length(priority_taxa),
        format(priority_budget, big.mark = ",")))
    }
  }

  # Compute per-taxon caps for the broad (family/genus) searches
  retmax_cap <- stats::setNames(counts, taxa)  # default: fetch everything

  if (total > max_sequences) {
    family_budget <- max(0L, max_sequences - priority_budget)
    valid <- !is.na(counts) & counts > 0L

    if (family_budget > 0L) {
      guarantee <- pmin(counts[valid], as.integer(min_per_taxon))
      remaining <- family_budget - sum(guarantee)

      if (remaining > 0L) {
        excess     <- pmax(counts[valid] - guarantee, 0L)
        total_excess <- sum(excess)
        if (total_excess > 0L) {
          bonus <- floor(excess / total_excess * remaining)
        } else {
          bonus <- rep(0L, sum(valid))
        }
        retmax_cap[valid] <- guarantee + bonus
      } else {
        # Budget exhausted by guarantees; give each the minimum possible
        retmax_cap[valid] <- pmin(counts[valid],
                                  pmax(1L, floor(family_budget / sum(valid))))
      }
    } else {
      # Priority species used entire budget; still give families a minimum
      retmax_cap[valid] <- pmin(counts[valid], as.integer(min_per_taxon))
    }
    retmax_cap[!valid] <- 0L

    total_plan <- sum(retmax_cap, na.rm = TRUE) + priority_budget
    message(sprintf(
      "Fetching up to %s sequences (%s priority + %s family-level).",
      format(total_plan, big.mark = ","),
      format(priority_budget, big.mark = ","),
      format(sum(retmax_cap, na.rm = TRUE), big.mark = ",")))
  }

  # --- Step 2a: Fetch priority species first ---------------------------------
  priority_meta <- list()

  if (length(priority_counts) > 0L && priority_budget > 0L) {
    message("\nFetching priority species sequences...")
    for (sp in names(priority_counts)) {
      if (priority_counts[[sp]] == 0L) next

      # Check cache
      p_cache_file <- NULL
      if (!is.null(cache_dir)) {
        safe_name <- gsub("[^A-Za-z0-9]", "_", sp)
        safe_bc   <- gsub("[^A-Za-z0-9]", "_", paste(barcode_term, collapse = "_"))
        p_cache_file <- file.path(cache_dir,
                                  paste0("priority_", safe_name, "_", safe_bc, "_meta.rds"))
        if (file.exists(p_cache_file)) {
          message(sprintf("  %s: loading from cache", sp))
          priority_meta[[sp]] <- readRDS(p_cache_file)
          next
        }
      }

      message(sprintf("  %s: fetching %s summaries...",
                      sp, format(priority_counts[[sp]], big.mark = ",")))
      tryCatch({
        sp_term <- .build_search_term(sp, barcode_term, min_date, max_date)
        search_obj <- rentrez::entrez_search(
          db = "nucleotide", term = sp_term,
          retmax = min(priority_counts[[sp]], 9999L), use_history = TRUE
        )
        meta <- .fetch_summaries_batched(search_obj)
        if (!is.null(meta) && nrow(meta) > 0L) {
          priority_meta[[sp]] <- meta
          if (!is.null(p_cache_file)) saveRDS(meta, p_cache_file)
        }
      }, error = function(e) {
        warning(sprintf("Priority fetch failed for '%s': %s", sp,
                        conditionMessage(e)), call. = FALSE)
      })
      Sys.sleep(delay)
    }
  }

  # --- Step 2b: Broader family/genus fetch ------------------------------------
  message("\nFetching broader taxonomic context...")
  all_meta <- vector("list", length(taxa))

  for (i in seq_along(taxa)) {
    if (is.na(counts[i]) || counts[i] == 0L) next

    # Check cache
    cache_file <- NULL
    if (!is.null(cache_dir)) {
      safe_name  <- gsub("[^A-Za-z0-9]", "_", taxa[i])
      safe_bc    <- gsub("[^A-Za-z0-9]", "_", paste(barcode_term, collapse = "_"))
      cache_file <- file.path(cache_dir, paste0(safe_name, "_", safe_bc, "_meta.rds"))
      if (file.exists(cache_file)) {
        message(sprintf("  %s: loading from cache", taxa[i]))
        all_meta[[i]] <- readRDS(cache_file)
        next
      }
    }

    fetch_n <- retmax_cap[[taxa[i]]]
    if (is.na(fetch_n) || fetch_n == 0L) next

    # Wrap entire per-taxon fetch in tryCatch so NCBI rate-limit or parse
    # errors skip one taxon instead of crashing the whole run.
    tryCatch({
      capped_msg <- if (fetch_n < counts[i])
        sprintf(" (capped from %s)", format(counts[i], big.mark = ",")) else ""
      message(sprintf("  %s: fetching %s summaries%s...",
                      taxa[i], format(fetch_n, big.mark = ","), capped_msg))

      term <- .build_search_term(taxa[i], barcode_term, min_date, max_date)
      search_obj <- rentrez::entrez_search(
        db = "nucleotide", term = term,
        retmax = min(fetch_n, 9999L), use_history = TRUE
      )

      # Summaries (lightweight: accession, taxid, length, title)
      meta <- .fetch_summaries_batched(search_obj)

      if (is.null(meta) || nrow(meta) == 0L) {
        warning(sprintf("No summaries retrieved for '%s'", taxa[i]),
                call. = FALSE)
        next
      }

      # Length filter (on summary metadata, before downloading sequences)
      meta <- meta[!is.na(meta$slen) &
                   meta$slen >= eff_min_len &
                   meta$slen <= eff_max_len, , drop = FALSE]

      # Blacklist filter
      if (!is.null(blacklist_regex) && nchar(blacklist_regex) > 0L) {
        meta <- meta[!grepl(blacklist_regex, meta$title, ignore.case = TRUE),
                     , drop = FALSE]
      }

      if (nrow(meta) == 0L) {
        message(sprintf("  %s: no sequences passed filters", taxa[i]))
        next
      }

      # Taxonomy bridge: taxid -> full lineage
      unique_taxids <- unique(meta$taxid)
      unique_taxids <- unique_taxids[!is.na(unique_taxids) &
                                      nchar(unique_taxids) > 0L]

      message(sprintf("  %s: resolving taxonomy for %d unique taxids...",
                      taxa[i], length(unique_taxids)))
      tax_map <- .fetch_taxonomy_map(unique_taxids, tolower(rank_system))

      if (is.null(tax_map) || nrow(tax_map) == 0L) {
        warning(sprintf("Taxonomy resolution failed for '%s'", taxa[i]),
                call. = FALSE)
        next
      }

      meta <- merge(meta, tax_map, by = "taxid", all.x = TRUE)

      # Drop rows with missing finest-rank taxonomy
      finest_rank <- tolower(rank_system[length(rank_system)])
      meta <- meta[!is.na(meta[[finest_rank]]), , drop = FALSE]

      # Filter to valid species names (reuse coverage.R helper pattern)
      if (finest_rank == "species") {
        meta <- meta[TaxaTools::is_valid_species_name(meta$species),
                     , drop = FALSE]
      }

      if (nrow(meta) == 0L) {
        message(sprintf("  %s: no sequences with valid taxonomy", taxa[i]))
        next
      }

      # Stratified downsampling
      if (!is.null(max_per_species) && finest_rank == "species") {
        meta <- dplyr::group_by(meta, species)
        meta <- dplyr::slice_sample(meta, n = max_per_species)
        meta <- dplyr::ungroup(meta)
      }
      if (!is.null(max_per_genus) && "genus" %in% tolower(rank_system)) {
        meta <- dplyr::group_by(meta, genus)
        meta <- dplyr::slice_sample(meta, n = max_per_genus)
        meta <- dplyr::ungroup(meta)
      }

      message(sprintf("  %s: %d sequences after filtering/downsampling",
                      taxa[i], nrow(meta)))

      all_meta[[i]] <- meta

      # Cache intermediate result
      if (!is.null(cache_file)) {
        saveRDS(meta, cache_file)
      }
    }, error = function(e) {
      warning(sprintf(
        "fetch_reference_sequences: '%s' failed (%s). Skipping this taxon.",
        taxa[i], conditionMessage(e)
      ), call. = FALSE)
    })
  }

  # --- Combine priority + family metadata -------------------------------------
  # Priority meta needs the same length/blacklist/taxonomy filtering applied
  # to family results. Process priority meta through the same pipeline.
  if (length(priority_meta) > 0L) {
    priority_combined <- do.call(rbind, Filter(Negate(is.null), priority_meta))
    if (!is.null(priority_combined) && nrow(priority_combined) > 0L) {
      # Length filter
      priority_combined <- priority_combined[
        !is.na(priority_combined$slen) &
        priority_combined$slen >= eff_min_len &
        priority_combined$slen <= eff_max_len, , drop = FALSE]
      # Blacklist filter
      if (!is.null(blacklist_regex) && nchar(blacklist_regex) > 0L) {
        priority_combined <- priority_combined[
          !grepl(blacklist_regex, priority_combined$title, ignore.case = TRUE),
          , drop = FALSE]
      }
      if (nrow(priority_combined) > 0L) {
        # Taxonomy resolution
        p_taxids <- unique(priority_combined$taxid)
        p_taxids <- p_taxids[!is.na(p_taxids) & nchar(p_taxids) > 0L]
        if (length(p_taxids) > 0L) {
          message(sprintf("Resolving taxonomy for %d priority taxids...",
                          length(p_taxids)))
          p_tax_map <- .fetch_taxonomy_map(p_taxids, tolower(rank_system))
          if (!is.null(p_tax_map) && nrow(p_tax_map) > 0L) {
            priority_combined <- merge(priority_combined, p_tax_map,
                                       by = "taxid", all.x = TRUE)
            finest_rank <- tolower(rank_system[length(rank_system)])
            priority_combined <- priority_combined[
              !is.na(priority_combined[[finest_rank]]), , drop = FALSE]
            if (finest_rank == "species") {
              priority_combined <- priority_combined[
                TaxaTools::is_valid_species_name(priority_combined$species),
                , drop = FALSE]
            }
          } else {
            priority_combined <- priority_combined[0L, , drop = FALSE]
          }
        }
        if (nrow(priority_combined) > 0L) {
          message(sprintf(
            "Priority species: %d sequences after filtering (%d species)",
            nrow(priority_combined),
            dplyr::n_distinct(priority_combined[[
              tolower(rank_system[length(rank_system)])]])))
        }
      }
    } else {
      priority_combined <- NULL
    }
  } else {
    priority_combined <- NULL
  }

  family_meta <- do.call(rbind, Filter(Negate(is.null), all_meta))

  # Merge: priority first, then family (deduplicate by accession)
  meta_parts <- Filter(Negate(is.null),
                       list(priority_combined, family_meta))
  combined_meta <- if (length(meta_parts) > 0L) do.call(rbind, meta_parts) else NULL

  if (is.null(combined_meta) || nrow(combined_meta) == 0L) {
    message("No sequences passed all filters across all taxa.")
    return(data.frame(
      composite_id = character(0L), sequence = character(0L),
      stringsAsFactors = FALSE
    ))
  }

  # Deduplicate by accession (priority sequences take precedence)
  combined_meta <- combined_meta[!duplicated(combined_meta$acc), , drop = FALSE]
  message(sprintf("\nFetching FASTA for %d sequences...", nrow(combined_meta)))

  # --- Step 3: Fetch FASTA sequences ------------------------------------------
  fasta_text <- .fetch_fasta_batched(combined_meta$acc)
  fasta_df   <- .parse_fasta_text(fasta_text)

  if (nrow(fasta_df) == 0L) {
    warning("FASTA download returned no sequences")
    return(data.frame(
      composite_id = character(0L), sequence = character(0L),
      stringsAsFactors = FALSE
    ))
  }

  # Strip version suffix from accessions in metadata for joining
  combined_meta$composite_id <- sub("\\.[0-9]+$", "", combined_meta$acc)

  # Join sequences to taxonomy
  rank_cols <- tolower(rank_system)
  keep_cols <- c("composite_id", rank_cols)
  lookup    <- combined_meta[!duplicated(combined_meta$composite_id), keep_cols,
                             drop = FALSE]

  reference_df <- merge(fasta_df, lookup, by = "composite_id", all.x = FALSE)
  reference_df <- reference_df[!is.na(reference_df$sequence) &
                                nchar(reference_df$sequence) > 0L, , drop = FALSE]

  finest_rank <- tolower(rank_system[length(rank_system)])
  message(sprintf("Done. reference_df: %d sequences, %d unique %s",
                  nrow(reference_df),
                  dplyr::n_distinct(reference_df[[finest_rank]]),
                  finest_rank))
  reference_df
}


# --- Internal helpers for taxonomy_file parsing in read_reference_fasta() ----

#' Standard 7-level hierarchy used for positional taxonomy-string parsing
#' @noRd
.crabs_std_hierarchy <- c("kingdom", "phylum", "class", "order",
                          "family", "genus", "species")

#' Parse one semicolon-delimited taxonomy string into named rank values
#'
#' Supports two formats:
#' \itemize{
#'   \item Prefix-style: \code{k__Kingdom;p__Phylum;...} (QIIME2 / RESCRIPt /
#'     SILVA). Also accepts \code{d__} (domain) as an alias for kingdom.
#'   \item Positional (no prefix): \code{Kingdom;Phylum;Class;Order;Family;Genus;Species}
#'     (MIDORI2, plain SILVA). Levels are matched left-to-right against
#'     \code{.crabs_std_hierarchy}.
#' }
#' @noRd
.parse_tax_string <- function(tax_string, rank_system) {
  parts <- strsplit(trimws(tax_string), ";", fixed = TRUE)[[1L]]
  parts <- trimws(parts)
  # Treat empty, bare "NA", and unclassified entries as missing
  parts[parts == "" | parts == "NA" |
        grepl("^unclassified$|^uncultured$", parts, ignore.case = TRUE)] <-
    NA_character_

  result <- stats::setNames(rep(NA_character_, length(rank_system)), rank_system)

  # Detect prefix-style by looking for pattern like "k__" or "d__" in any part
  non_na    <- parts[!is.na(parts)]
  has_prefix <- length(non_na) > 0L && any(grepl("^[a-z]__", non_na))

  if (has_prefix) {
    # Map single-letter prefix to canonical rank name
    prefix_map <- c(k = "kingdom", d = "kingdom", p = "phylum", c = "class",
                    o = "order",   f = "family",   g = "genus", s = "species")
    for (p in non_na) {
      m <- regmatches(p, regexpr("^([a-z])__(.+)$", p, perl = TRUE))
      if (length(m) == 0L || !nzchar(m)) next
      prefix <- substr(p, 1L, 1L)
      val    <- sub("^[a-z]__", "", p)
      if (!nzchar(val)) next
      rank <- prefix_map[prefix]
      if (!is.na(rank) && rank %in% rank_system)
        result[[rank]] <- val
    }
  } else {
    # Positional mapping against standard 7-level hierarchy
    for (k in seq_along(parts)) {
      if (k > length(.crabs_std_hierarchy)) break
      rank <- .crabs_std_hierarchy[k]
      if (rank %in% rank_system && !is.na(parts[k]))
        result[[rank]] <- parts[k]
    }
  }
  result
}

#' Parse a 2-column taxonomy TSV file (QIIME2, RESCRIPt, SILVA, MIDORI2)
#'
#' Column 1: sequence ID. Column 2: semicolon-separated taxonomy string.
#' Header rows whose first token starts with "Feature" or "feature" or
#' "seq_id" are detected and skipped automatically.
#' @noRd
.parse_taxonomy_tsv <- function(taxonomy_file, rank_system) {
  raw <- tryCatch(
    utils::read.table(
      taxonomy_file, sep = "\t", header = FALSE,
      col.names      = c("seq_id", "tax_string"),
      quote          = "",  comment.char = "",
      stringsAsFactors = FALSE, fill = TRUE
    ),
    error = function(e)
      stop(sprintf("Failed to read taxonomy file '%s': %s",
                   basename(taxonomy_file), conditionMessage(e)))
  )

  if (nrow(raw) == 0L)
    stop(sprintf("Taxonomy file is empty: %s", basename(taxonomy_file)))

  # Skip header rows: first field starts with "Feature", "feature", or "seq_id"
  if (grepl("^[Ff]eature|^seq.?id|^#", raw[1L, 1L])) raw <- raw[-1L, , drop = FALSE]

  if (nrow(raw) == 0L)
    stop(sprintf("Taxonomy file contained only a header row: %s",
                 basename(taxonomy_file)))

  # Strip version suffixes from IDs for consistent matching with FASTA headers
  raw$seq_id <- sub("\\.[0-9]+$", "", trimws(raw$seq_id))

  # Parse unique taxonomy strings (many rows share the same string -- parse once)
  unique_strings <- unique(raw$tax_string)
  parsed_map     <- lapply(unique_strings, .parse_tax_string, rank_system = rank_system)
  names(parsed_map) <- unique_strings

  # Build result data frame
  result_list <- lapply(seq_len(nrow(raw)), function(i) {
    row <- parsed_map[[raw$tax_string[i]]]
    c(composite_id = raw$seq_id[i], row)
  })

  out <- do.call(rbind, lapply(result_list, function(x) as.data.frame(
    as.list(x), stringsAsFactors = FALSE
  )))
  row.names(out) <- NULL
  out
}


#' Read a local FASTA file into a reference data frame
#'
#' Reads a FASTA file and joins it to a user-supplied taxonomy table to produce
#' a `reference_df` suitable for [build_sequence_matrix()].
#'
#' This is the local-file alternative to [fetch_reference_sequences()].
#' Use it when you already have a reference database on disk (e.g., a CRUX
#' database, a GenBank download, or a custom curated FASTA).
#'
#' @section CRABS databases:
#' If your FASTA was produced by CRABS, use [read_crabs_output()] on the
#' CRABS internal-format file instead.  It reads the taxonomy embedded
#' directly in that file without requiring a separate taxonomy table.
#'
#' @section Taxonomy table format:
#' The taxonomy table must contain a `composite_id` column that matches the
#' identifiers extracted from FASTA headers, plus one column per rank in your
#' `rank_system`.
#' FASTA header identifiers are extracted as the first whitespace-delimited
#' token after `>`, with version suffixes (`.1`, `.2`) stripped.
#'
#' Example:
#' \preformatted{
#'   composite_id,  family,       genus,       species
#'   NC_001606,     Fundulidae,   Fundulus,    Fundulus heteroclitus
#'   NC_012361,     Fundulidae,   Fundulus,    Fundulus parvipinnis
#' }
#'
#' @section Taxonomy file format (QIIME2 / RESCRIPt / SILVA / MIDORI2):
#' Supply `taxonomy_file` instead of `taxonomy` when your taxonomy lives in a
#' 2-column tab-delimited file where column 1 is the sequence ID and column 2
#' is a semicolon-delimited taxonomy string.  Two sub-formats are supported:
#' \itemize{
#'   \item \strong{Prefix-style} (QIIME2, RESCRIPt, SILVA):
#'     \code{k__Kingdom;p__Phylum;c__Class;o__Order;f__Family;g__Genus;s__Species}
#'   \item \strong{Positional} (MIDORI2, plain SILVA):
#'     \code{Kingdom;Phylum;Class;Order;Family;Genus;Species}
#' }
#' A single header row starting with \code{Feature} or \code{feature} is
#' automatically detected and skipped.
#'
#' @param fasta_path Character scalar.
#'   Path to a FASTA file (`.fasta`, `.fa`, `.fna`).
#' @param taxonomy Data frame with a `composite_id` column and one column per
#'   rank in your rank system.
#'   `composite_id` values must match the accessions parsed from FASTA headers.
#'   Supply either `taxonomy` or `taxonomy_file`, not both.
#' @param rank_system Character vector of rank names, **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`).
#'   Used to validate that all rank columns are present in `taxonomy`, or to
#'   determine which ranks to extract from `taxonomy_file`.
#' @param taxonomy_file Character scalar or \code{NULL} (default).
#'   Path to a 2-column taxonomy TSV file (see section above).
#'   Supply either `taxonomy_file` or `taxonomy`, not both.
#'   Requires `rank_system` to be specified explicitly.
#'
#' @return A data frame (`reference_df`) with columns `composite_id`,
#'   `sequence`, and one column per rank.
#'   Ready for input to [build_sequence_matrix()].
#'
#' @seealso [read_crabs_output()] for CRABS internal-format files,
#'   [fetch_reference_sequences()] for downloading from NCBI,
#'   [build_sequence_matrix()]
#'
#' @examples
#' \dontrun{
#' # Option A: data frame taxonomy (existing behaviour)
#' tax <- data.frame(
#'   composite_id = c("ACC001", "ACC002"),
#'   family = c("Fundulidae", "Atherinopsidae"),
#'   genus  = c("Fundulus", "Atherinops"),
#'   species = c("Fundulus parvipinnis", "Atherinops affinis")
#' )
#' ref <- read_reference_fasta("my_references.fasta", tax,
#'                             rank_system = c("family", "genus", "species"))
#'
#' # Option B: QIIME2/RESCRIPt taxonomy file (prefix-style)
#' ref <- read_reference_fasta(
#'   "sequences.fasta",
#'   rank_system   = c("family", "genus", "species"),
#'   taxonomy_file = "taxonomy.tsv"
#' )
#' }
#'
#' @export
read_reference_fasta <- function(fasta_path, taxonomy = NULL, rank_system,
                                 taxonomy_file = NULL) {
  if (!is.character(fasta_path) || length(fasta_path) != 1L)
    stop("fasta_path must be a single file path")
  if (!file.exists(fasta_path))
    stop(sprintf("File not found: %s", fasta_path))
  if (file.info(fasta_path)$size == 0L)
    stop(sprintf("FASTA file is empty (0 bytes): %s", fasta_path))
  if (!is.null(taxonomy) && !is.null(taxonomy_file))
    stop("Supply either 'taxonomy' or 'taxonomy_file', not both")
  if (is.null(taxonomy) && is.null(taxonomy_file))
    stop("One of 'taxonomy' or 'taxonomy_file' must be supplied")

  rank_cols <- tolower(rank_system)

  # --- Resolve taxonomy -------------------------------------------------------
  if (!is.null(taxonomy_file)) {
    # Parse taxonomy from a TSV file (QIIME2 / RESCRIPt / SILVA / MIDORI2)
    if (!is.character(taxonomy_file) || length(taxonomy_file) != 1L)
      stop("taxonomy_file must be a single file path")
    if (!file.exists(taxonomy_file))
      stop(sprintf("taxonomy_file not found: %s", taxonomy_file))
    taxonomy <- .parse_taxonomy_tsv(taxonomy_file, rank_cols)
  }

  if (!is.data.frame(taxonomy))
    stop("taxonomy must be a data frame")

  names(taxonomy) <- tolower(names(taxonomy))

  needed <- c("composite_id", rank_cols)
  missing_cols <- setdiff(needed, names(taxonomy))
  if (length(missing_cols) > 0L)
    stop(sprintf("taxonomy is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))

  # Read and parse FASTA
  fasta_text <- paste(readLines(fasta_path, warn = FALSE), collapse = "\n")
  fasta_df   <- .parse_fasta_text(fasta_text)

  if (nrow(fasta_df) == 0L)
    stop("No sequences found in FASTA file (no headers detected)")

  # Check for headers-only (no actual sequence data)
  has_seq <- nchar(fasta_df$sequence) > 0L
  if (!any(has_seq))
    stop("FASTA file contains headers but no sequence data")
  if (any(!has_seq)) {
    n_empty <- sum(!has_seq)
    message(sprintf("Warning: %d header(s) with no sequence data will be dropped", n_empty))
    fasta_df <- fasta_df[has_seq, , drop = FALSE]
  }

  message(sprintf("Parsed %d sequences from %s", nrow(fasta_df), fasta_path))

  # Also strip version suffix from taxonomy composite_id for matching
  taxonomy$composite_id <- sub("\\.[0-9]+$", "", taxonomy$composite_id)

  # Join
  keep_cols    <- c("composite_id", rank_cols)
  lookup       <- taxonomy[!duplicated(taxonomy$composite_id), keep_cols,
                           drop = FALSE]
  reference_df <- merge(fasta_df, lookup, by = "composite_id", all.x = FALSE)
  reference_df <- reference_df[!is.na(reference_df$sequence) &
                                nchar(reference_df$sequence) > 0L, , drop = FALSE]

  n_unmatched <- nrow(fasta_df) - nrow(reference_df)
  if (n_unmatched > 0L)
    message(sprintf("%d sequence(s) had no taxonomy match and were dropped",
                    n_unmatched))

  message(sprintf("reference_df: %d sequences", nrow(reference_df)))
  reference_df
}
