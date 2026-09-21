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

  # Bare mitochondrial rRNA marker names ("12S"/"16S") have neither a [GENE]
  # field tag NOR a primer-name entry above, so with no fix they fall through
  # to a bare "12S[All Fields]"/"16S[All Fields]" search -- which is unreliable:
  # confirmed live against NCBI that a real, correctly-annotated, correctly-
  # sized Fundulus parvipinnis 12S rRNA sequence (OQ846298, /product="small
  # subunit ribosomal RNA") matches ZERO results for "12S[All Fields]" alone,
  # purely because neither the record itself nor its own citation happens to
  # contain the literal string "12S" anywhere -- while a near-identical
  # congener submission (OP537863) WAS found, only because ITS linked
  # citation was titled "12S barcoding of Texas fishes". Whether a genuine
  # 12S/16S sequence is found was effectively down to incidental bibliographic
  # metadata, not the sequence's own real content. "Small/large subunit
  # ribosomal RNA" (SSU/LSU rRNA) are the standard, unambiguous synonyms for
  # mitochondrial 12S/16S rRNA specifically (confirmed empirically too: this
  # phrasing recovers 1 additional real Fundulus 12S record and 3 additional
  # real Fundulus 16S records beyond what a bare marker-name search finds).
  # Deliberately NOT extended to 18S: "small subunit ribosomal RNA" is
  # ambiguous between mitochondrial 12S and NUCLEAR 18S, so reusing it there
  # would trade missed true positives for new false positives -- a different
  # risk profile needing its own design, not a copy of this fix.
  marker_synonyms <- list(
    "12s" = c('"12S ribosomal RNA"', '"12S rRNA"', '"small subunit ribosomal RNA"'),
    "16s" = c('"16S ribosomal RNA"', '"16S rRNA"', '"large subunit ribosomal RNA"')
  )

  # A registered PRIMER-VARIANT name (TaxaTools::barcode_primer_defaults) is the
  # right term for resolving primers and amplicon lengths, but it is NOT a term
  # NCBI indexes -- no GenBank record is tagged "Folmer" or "Palumbi". Without
  # this map every variant except the MiFish pair (covered by primer_to_locus
  # below) fell through to a bare "<variant>[All Fields]" search and returned
  # ZERO hits for every taxon, silently: the fetch reports "No sequences found.
  # Check taxon names and barcode_term." and hands back an empty reference_df,
  # which then fails downstream in clean_taxon_names() on a NULL species column.
  # Found live when a workflow's COI term was changed "COI" -> "COI-Folmer" to
  # resolve a genuine resolve_barcode_primers() ambiguity: 23/23 genera, 0 hits.
  # Resolve the variant to the marker it amplifies, then search as that marker.
  # The map lives in TaxaTools (resolve_barcode_marker) because the identical
  # silent failure reaches multiple call sites -- here, audit_barcode_coverage(),
  # and suggest_unreferenced_species() -- and TaxaTools already owns the
  # primer/length registries these terms come from.
  bc_parts <- vapply(barcode_term, function(bt) {
    key <- tolower(trimws(bt))
    resolved <- TaxaTools::resolve_barcode_marker(bt)
    base_key <- if (!identical(tolower(trimws(resolved)), key)) {
      tolower(trimws(resolved))
    } else {
      NA_character_
    }
    if (!is.na(base_key)) {
      # Search as the base marker in every clause, so a remapped term produces
      # exactly the query the bare marker name would have produced -- never a
      # dead "<variant>[All Fields]" clause.
      key <- base_key
      bt <- toupper(base_key)
    }
    gene <- gene_map[key]
    if (!is.na(gene)) {
      # Known gene name: use [GENE] field directly
      paste0(gene, "[GENE]")
    } else {
      # Primer name or unrecognised term: search [All Fields]
      primer_clause <- paste0(bt, "[All Fields]")
      # Also OR in the underlying locus if known
      locus <- primer_to_locus[key]
      synonyms <- marker_synonyms[[key]]
      clauses <- primer_clause
      if (!is.na(locus)) clauses <- c(clauses, paste0(locus, "[All Fields]"))
      if (!is.null(synonyms)) clauses <- c(clauses, paste0(synonyms, "[All Fields]"))
      if (length(clauses) > 1L) {
        paste0("(", paste(clauses, collapse = " OR "), ")")
      } else {
        clauses
      }
    }
  }, character(1L), USE.NAMES = FALSE)

  bc_clause <- if (length(bc_parts) == 1L) {
    bc_parts
  } else {
    paste0("(", paste(bc_parts, collapse = " OR "), ")")
  }

  # Normalise hyphens in taxon name before building the query term.
  term <- paste0(gsub("-", " ", taxon), "[Organism] AND ", bc_clause)

  # Date clause (PDAT = publication date)

  if (!is.null(min_date) || !is.null(max_date)) {
    d_start <- if (!is.null(min_date)) min_date else "1900/01/01"
    d_end <- if (!is.null(max_date)) max_date else "3000/12/31"
    term <- paste0(term, " AND (", d_start, "[PDAT] : ", d_end, "[PDAT])")
  }

  term
}


#' Retry a single fetch/parse attempt closure up to max_attempts times
#'
#' Shared retry shape for `.fetch_summaries_batched()`/`.fetch_taxonomy_map()`/
#' `.fetch_fasta_batched()`/`.fetch_locations_batched()`, each of which
#' hand-rolled an identical 3-attempt linear-backoff loop around one NCBI
#' round trip. `fn` is a zero-argument closure that performs one attempt
#' (fetch + parse) and returns that attempt's result; any error it throws is
#' caught and retried, with `Sys.sleep(attempt)` between attempts (no sleep
#' after the final attempt). On exhaustion, all four original call sites
#' failed silently (no warning/error, the caller's pre-allocated slot for
#' this batch simply stayed at its initial empty value) -- `success = FALSE`
#' preserves that: the caller must check it before using `value` (see
#' `@return`).
#' @param fn Zero-argument closure performing one fetch attempt.
#' @param max_attempts Integer (default `3L`), matching every original call
#'   site.
#' @return `list(value, success)` -- `value` is `fn()`'s result on success
#'   (`NULL` if every attempt failed); `success` is `TRUE` only if some
#'   attempt succeeded.
#' @noRd
.retry_fetch <- function(fn, max_attempts = 3L) {
  attempt <- 0L
  success <- FALSE
  value <- NULL
  while (attempt < max_attempts && !success) {
    attempt <- attempt + 1L
    tryCatch(
      {
        value <- fn()
        success <- TRUE
      },
      error = function(e) {
        if (attempt < max_attempts) Sys.sleep(attempt)
      }
    )
  }
  list(value = value, success = success)
}


#' Fetch NCBI summaries in batches (lightweight: accession, taxid, length)
#' @noRd
.fetch_summaries_batched <- function(search_obj, batch_size = 200L) {
  total <- as.integer(search_obj$count)
  starts <- seq(0L, total - 1L, by = batch_size)
  res <- vector("list", length(starts))

  for (i in seq_along(starts)) {
    result <- .retry_fetch(function() {
      summ <- rentrez::entrez_summary(
        db          = "nucleotide",
        web_history = search_obj$web_history,
        retstart    = starts[i],
        retmax      = batch_size
      )
      # entrez_summary returns a single item or a list of items
      if (!is.null(summ$uid)) summ <- list(summ)

      # dplyr::bind_rows(), not do.call(rbind, ...) -- a handful of real
      # NCBI ESummary records can come back missing a field entirely
      # (already handled per-field above via is.null() -> NA), but the
      # real risk is heterogeneous per-record structure from rentrez
      # itself under retry/partial-failure conditions; rbind() errors on
      # any column mismatch where bind_rows() fills the gap with NA (same
      # fix already applied to the BOLD fetch path, see fetch_bold_
      # reference_sequences() below for the identical reasoning).
      dplyr::bind_rows(lapply(summ, function(x) {
        data.frame(
          acc = as.character(if (is.null(x$caption)) NA else x$caption),
          # acc_version: the SAME accession WITH its version suffix
          # ("AB000667.1" where `caption` gives "AB000667"). Live-verified
          # on this same already-batched ESummary call -- zero extra NCBI
          # round trips, exactly like create_date below.
          #
          # `acc` deliberately stays the UNVERSIONED caption: it is what
          # composite_id is derived from, what .fetch_locations_batched()
          # must be joined on (GBSeq_primary-accession carries no version),
          # and what the accession dedupe just above relies on to collapse
          # two revisions of one record. acc_version exists solely to key
          # the FASTA store -- see .fetch_fasta_cached().
          acc_version = as.character(
            if (is.null(x$accessionversion)) NA else x$accessionversion
          ),
          title = as.character(if (is.null(x$title)) NA else x$title),
          taxid = as.character(if (is.null(x$taxid)) NA else x$taxid),
          slen = as.numeric(if (is.null(x$slen)) NA else x$slen),
          organism = as.character(if (is.null(x$organism)) NA else x$organism),
          # create_date: live-verified (rentrez::entrez_summary(db =
          # "nucleotide", ...)) that NCBI's own ESummary DocSum for this
          # database includes a real createdate field ("YYYY/MM/DD") on the
          # same already-batched call this function makes -- zero extra NCBI
          # round trips. Used by .compute_hierarchy_congruence()'s
          # independence filter (audit_reference_database.R) to detect
          # same-submission-batch accessions.
          create_date = as.character(if (is.null(x$createdate)) NA else x$createdate),
          stringsAsFactors = FALSE
        )
      }))
    })
    if (result$success) res[[i]] <- result$value
  }

  dplyr::bind_rows(res)
}


#' Fetch full taxonomy lineage from NCBI taxonomy DB via taxids
#' @noRd
.fetch_taxonomy_map <- function(taxids, desired_ranks, batch_size = 100L) {
  batches <- split(taxids, ceiling(seq_along(taxids) / batch_size))
  res <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    result <- .retry_fetch(function() {
      xml_raw <- rentrez::entrez_fetch(
        db = "taxonomy", id = batches[[i]], rettype = "xml"
      )
      xml_doc <- xml2::read_xml(xml_raw)
      nodes <- xml2::xml_find_all(xml_doc, "//TaxaSet/Taxon")

      parsed <- lapply(nodes, function(node) {
        this_id <- xml2::xml_text(xml2::xml_find_first(node, "./TaxId"))
        this_sci <- xml2::xml_text(xml2::xml_find_first(node, "./ScientificName"))
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

      # dplyr::bind_rows(), not do.call(rbind, ...) -- real NCBI taxonomy
      # XML is not perfectly uniform across taxids (e.g. a merged/redirected
      # taxon's <Taxon> node can carry a different internal shape), so
      # `parsed`'s per-node data frames can't be guaranteed to share
      # identical columns; rbind() hard-errors on any mismatch
      # ("numbers of columns of arguments do not match", confirmed live
      # against a real ~1300-genus PtConception 18S fetch), bind_rows()
      # fills the gap with NA instead. Same fix as .fetch_summaries_
      # batched() above and the BOLD fetch path.
      dplyr::bind_rows(parsed)
    })
    if (result$success) res[[i]] <- result$value
    Sys.sleep(.ncbi_delay())
  }

  dplyr::bind_rows(res)
}


#' Selection parameters that shape a cached object but are NOT in its key
#'
#' The reference-cache key captures everything that decides
#' which sequences are FETCHED (barcode_term, length and date bounds,
#' rank_system, the out-of-range flags) but not everything that decides
#' which are KEPT. The cached object is written after blacklist filtering
#' and after \code{slice_sample()} downsampling (\code{fetch.R}, "Blacklist
#' filter" and the \code{max_per_species}/\code{max_per_genus} block), so a
#' cache built with \code{max_per_species = 10} would be served unchanged to
#' a later call asking for 50 -- silently under-filled, the same class of
#' quiet degradation the \code{barcode_term} and \code{rank_system} fields in
#' the cache key exist to prevent for those parameters.
#'
#' Widening the key again would orphan every existing cache file at
#' once, which is the growth mechanism the \code{.ref_cache_grammar()}-based
#' eviction exists to stop. So
#' instead these parameters are STORED INSIDE the cached object and verified
#' on read: a mismatch is a cache miss, and nothing is orphaned. A cached
#' file written before this attribute existed cannot be verified; it is
#' accepted, with one warning per call naming how many.
#' @noRd
.sel_params <- function(max_per_species, max_per_genus, blacklist_regex) {
  list(
    max_per_species = max_per_species,
    max_per_genus = max_per_genus,
    blacklist_regex = blacklist_regex
  )
}

#' Is a cached object's stored selection parameters compatible with this call?
#'
#' Returns "ok" or "mismatch" (cache miss -- re-fetch). A cached object with
#' no \code{sel_params} attribute at all -- one written before this
#' attribute existed -- cannot be verified against the current call and is
#' therefore a mismatch exactly like one recorded under different settings:
#' neither can be trusted to reflect \code{current}, and there is no way to
#' tell the two cases apart from the object alone, so they get the one
#' honest answer both deserve.
#' @noRd
.sel_params_status <- function(meta, current) {
  if (identical(attr(meta, "sel_params"), current)) "ok" else "mismatch"
}


#' The invariant head of a reference-cache file name: prefix + taxon + barcode
#'
#' Everything before the first key component that has ever been added,
#' removed or made conditional. Two files share a stem exactly when they are
#' successive cache generations for the SAME taxon and the SAME barcode, so
#' this is what scopes eviction to one taxon rather than prefix-matching,
#' which would let \code{Abudefduf_} also match \code{Abudefduf_saxatilis_}.
#' @noRd
.ref_cache_stem <- function(name, barcode_term, prefix = "") {
  paste0(
    prefix,
    gsub("[^A-Za-z0-9]", "_", name), "_",
    gsub("[^A-Za-z0-9]", "_", paste(barcode_term, collapse = "_"))
  )
}


#' Build the cache-file path for one taxon's reference metadata
#'
#' Single source of truth for the reference-cache key, so the priority and
#' broad-search paths cannot drift apart, and so the key can be computed
#' BEFORE the count query (see the "cache before
#' count" note in \code{fetch_ncbi_reference_sequences()}).
#'
#' Every argument that shapes the CONTENT of the cached object is part of
#' the key -- dropping any of them can silently serve a stale cache:
#' \code{barcode_term} (governs which sequences are fetched),
#' \code{rank_system} (the cached object is post-taxonomy-merge, so a
#' narrower rank_system's cache hard-crashes a wider call at the
#' \code{keep_cols} subset), \code{keep_out_of_range} (the cached object is
#' fully post-filter, so a cache built with FALSE genuinely lacks
#' out-of-range rows), and the length and date bounds.
#' @noRd
.ref_cache_file <- function(cache_dir, name, barcode_term, min_len, max_len,
                            min_date, max_date, keep_out_of_range,
                            max_out_of_range_per_species,
                            max_out_of_range_len, rank_system, prefix = "") {
  if (is.null(cache_dir)) {
    return(NULL)
  }
  stem <- .ref_cache_stem(name, barcode_term, prefix)
  date_sfx <- gsub("[^0-9]", "", paste0(
    if (is.null(min_date)) "X" else min_date, "_",
    if (is.null(max_date)) "X" else max_date
  ))
  oor_sfx <- if (keep_out_of_range) {
    sprintf("_oor%d_l%d", max_out_of_range_per_species, max_out_of_range_len)
  } else {
    ""
  }
  rank_sfx <- paste0("_rk-", paste(tolower(rank_system), collapse = "-"))
  file.path(
    cache_dir,
    paste0(
      stem,
      "_l", min_len, "_", max_len,
      "_d", date_sfx, oor_sfx, rank_sfx, "_meta.rds"
    )
  )
}


#' Every file name `.ref_cache_file()` can produce, as one regular expression
#'
#' Content-keyed caching with no eviction does
#' not REPLACE a generation when the key changes -- it DOUBLES it. Every
#' widening above was correct and was made in response to a real staleness
#' crash, and every one silently orphaned the entire previous generation:
#' confirmed on a real cache directory, 1,584 of 3,517 meta files (45%)
#' predated the \code{rank_sfx} widening.
#'
#' This is the eviction primitive, and it is a PROOF rather than a
#' heuristic. \code{rank_sfx} is appended unconditionally, so no argument
#' combination can produce a name lacking \code{_rk-}; more generally, a
#' file whose name this grammar does not match cannot be produced by the
#' current \code{.ref_cache_file()} for ANY arguments, and therefore can
#' never be hit again. That is what makes deleting it safe.
#'
#' \strong{Keep this in lockstep with \code{.ref_cache_file()}.} A widening
#' that is not reflected here leaves the superseded generation on disk
#' forever; a widening reflected here but not in the key would delete LIVE
#' files. \code{test-fetch-cache-eviction.R} pins the two together by
#' generating names over a grid of argument combinations and asserting every
#' one matches.
#'
#' Note what it deliberately does NOT cover: two files differing only in
#' their length bounds (\code{_l100_600} vs \code{_l100_5000}) are different
#' QUERIES, not successive generations, and a caller may legitimately want
#' both. Same for two different \code{rank_system} sets -- both are in live
#' use here (12S/18S use family-genus-species, GreatLakes the seven-rank
#' system). Only an unproducible SHAPE is evictable.
#' @noRd
.ref_cache_grammar <- function() {
  paste0(
    "^.+", # stem: prefix + sanitised taxon + sanitised barcode
    "_l[0-9]+_[0-9]+", # length window
    "_d[0-9]*", # date bounds; digits only, empty when both are NULL
    "(_oor[0-9]+_l[0-9]+)?", # out-of-range settings, only when kept
    "_rk-[a-z0-9-]*", # rank_system -- UNCONDITIONAL, hence the proof
    "_meta\\.rds$"
  )
}


#' Reference-cache files in `cache_dir` that no call can ever hit again
#'
#' Non-recursive by design: the \code{fasta/} store is a different
#' file-per-key cache with a different key, and nothing here can reason
#' about it.
#'
#' @param cache_dir Directory to scan.
#' @param stem Optional. When supplied, restrict the result to files sharing
#'   this \code{.ref_cache_stem()} -- i.e. the same taxon and barcode. This
#'   is the scoping used by the automatic write-path eviction; the explicit
#'   whole-store sweep passes \code{NULL}.
#' @return Character vector of full paths, possibly empty.
#' @noRd
.ref_cache_unreachable <- function(cache_dir, stem = NULL) {
  if (is.null(cache_dir) || !dir.exists(cache_dir)) {
    return(character(0L))
  }
  f <- list.files(cache_dir, pattern = "_meta\\.rds$", full.names = TRUE)
  if (length(f) == 0L) {
    return(character(0L))
  }
  f <- f[!grepl(.ref_cache_grammar(), basename(f))]
  if (length(f) == 0L || is.null(stem)) {
    return(f)
  }
  f[.ref_cache_stem_of(basename(f)) == stem]
}


#' Recover the stem from an existing cache-file name
#'
#' Parses right-to-left, because the stem itself can contain underscores
#' (a taxon name with a space, a multi-term barcode) while every key
#' component appended after it cannot.
#' @noRd
.ref_cache_stem_of <- function(basenames) {
  x <- sub("_meta\\.rds$", "", basenames)
  x <- sub("_rk-[a-z0-9-]*$", "", x)
  x <- sub("_oor[0-9]+_l[0-9]+$", "", x)
  x <- sub("_d[0-9]*$", "", x)
  sub("_l[0-9]+_[0-9]+$", "", x)
}


#' Largest file the automatic write-path eviction will delete without asking
#'
#' Auto-evicts the small metadata \code{.rds}
#' files; anything large reports and waits for an explicit call. A meta file
#' is ~1 KB, so in practice this never fires -- it is a structural guard, so
#' that a future cache object growing by three orders of magnitude cannot
#' quietly turn an automatic sweep into a multi-gigabyte deletion.
#' @noRd
.REF_CACHE_AUTO_EVICT_MAX_MB <- 5


#' Delete the unreachable cache files for one taxon, and say what went
#'
#' Called from the cache WRITE path only: a run that writes a new generation
#' for a taxon is exactly the moment the old generation for that taxon
#' becomes dead weight, which is what turns a future key widening from
#' "doubles the cache" into "replaces it". Scoped to one stem and to the
#' provable case; the whole-store sweep is the explicit, dry-run-by-default
#' \code{taxalikely_evict_unreachable_cache()}.
#' @noRd
.ref_cache_evict <- function(cache_dir, stem) {
  dead <- .ref_cache_unreachable(cache_dir, stem = stem)
  if (length(dead) == 0L) {
    return(invisible(0L))
  }
  mb <- file.size(dead) / 1024^2
  big <- !is.na(mb) & mb > .REF_CACHE_AUTO_EVICT_MAX_MB
  if (any(big)) {
    message(sprintf(
      "  Cache: %d unreachable file(s) over %g MB left in place; remove with taxalikely_evict_unreachable_cache().",
      sum(big), .REF_CACHE_AUTO_EVICT_MAX_MB
    ))
    dead <- dead[!big]
    mb <- mb[!big]
  }
  if (length(dead) == 0L) {
    return(invisible(0L))
  }
  gone <- file.remove(dead)
  message(sprintf(
    "  Cache: evicted %d superseded file(s) (%.0f KB) for this taxon -- older key shape, unreachable.",
    sum(gone), sum(mb[gone]) * 1024
  ))
  invisible(sum(gone))
}


#' Download FASTA sequences in batches
#' @noRd
.fetch_fasta_batched <- function(accessions, batch_size = 200L) {
  batches <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  chunks <- vector("character", length(batches))

  for (i in seq_along(batches)) {
    result <- .retry_fetch(function() {
      rentrez::entrez_fetch(
        db = "nucleotide", id = batches[[i]],
        rettype = "fasta", retmode = "text"
      )
    })
    if (result$success) chunks[i] <- result$value
    Sys.sleep(.ncbi_delay())
  }

  paste(chunks[nchar(chunks) > 0L], collapse = "\n")
}


#' Choose the accession string the FASTA store is keyed on
#'
#' The FASTA cache is keyed on \code{meta$acc}, which comes
#' from ESummary's \code{caption} field and carries NO version suffix
#' (confirmed on disk: cached files do not carry a version).
#'
#' The consequence is narrow but real. When a taxon's metadata is REFRESHED
#' and GenBank has revised a record since, an unversioned key would be a
#' cache HIT, silently serving the superseded sequence under the new
#' metadata. The download and parse paths were already written for versioned
#' input (the parser strips versions from FASTA headers, and the write-back
#' maps those stripped ids back to the string that was requested) -- only the
#' input was wrong.
#'
#' \strong{A row with no usable \code{acc_version} is therefore never
#' cacheable.} It cannot supply a version, and it also cannot NOTICE one: its
#' accession list is frozen at the moment it was cached, so no revision is
#' visible from it in the first place -- there is no key that would be safe
#' to persist and reuse for it. \code{.fetch_fasta_cached()}'s
#' \code{cacheable} argument (fed from this function's \code{cacheable}
#' attribute) makes that row a cache MISS unconditionally: always
#' downloaded fresh, never read from or written to the \code{fasta/} store.
#' A row's own metadata cache entry catching up (a re-fetch that rewrites
#' the meta with \code{acc_version} populated) is what turns it cacheable
#' again -- nothing here special-cases it.
#'
#' Resolved per ROW, so one record missing \code{accessionversion} costs
#' only its own version check rather than the whole taxon's.
#'
#' @param meta A combined metadata frame with an \code{acc} column and,
#'   when written by a current fetch, an \code{acc_version} column.
#' @return Character vector of cache/request accessions, one per row of
#'   \code{meta}, carrying a logical \code{cacheable} attribute (\code{FALSE}
#'   for rows with no usable version) and an integer \code{n_unversioned}
#'   attribute counting how many that is.
#' @noRd
.fasta_cache_keys <- function(meta) {
  acc <- as.character(meta$acc)
  ver <- if ("acc_version" %in% names(meta)) {
    as.character(meta$acc_version)
  } else {
    rep(NA_character_, length(acc))
  }
  ver <- rep(ver, length.out = length(acc))
  usable <- !is.na(ver) & nzchar(ver)
  out <- ifelse(usable, ver, acc)
  attr(out, "cacheable") <- usable
  attr(out, "n_unversioned") <- sum(!usable)
  out
}


#' Fetch FASTA for a set of accessions, reusing a per-accession cache
#'
#' The FASTA download is the largest
#' uncached cost in \code{fetch_ncbi_reference_sequences()} -- 3,983
#' sequences on a routine PtConception 12S run, re-downloaded in full every
#' time even when all 222 taxa' metadata came straight off disk.
#'
#' Keyed on the accession AS SUPPLIED by the caller, which is what decides
#' whether a GenBank version bump is caught -- see \code{.fasta_cache_keys()}
#' directly above for how that vector is chosen. An accession with no
#' recorded version has no key that would be safe to persist and reuse, so
#' \code{cacheable} (aligned with \code{accessions}, from
#' \code{.fasta_cache_keys()}'s own \code{cacheable} attribute) marks those
#' as an unconditional cache MISS: never read from disk even if a stale
#' file of that name exists, and never written back either.
#' Requesting the same string it keys on means the record NCBI returns is
#' the record the key names.
#'
#' One small .rds per accession under a \code{fasta/} subdirectory of
#' \code{cache_dir}, matching the file-per-key shape the rest of this
#' ecosystem uses, so \code{TaxaTools::list_cache_files()} (which
#' scans recursively) can see this store too.
#' A sequence that fails to download is simply not written, so the next run
#' retries it -- which is also what happens if a requested version has since
#' been replaced, since NCBI returns no record for a superseded version
#' rather than erroring (confirmed against a live NCBI query).
#' @noRd
.fetch_fasta_cached <- function(accessions, cache_dir, batch_size = 200L,
                                 cacheable = rep(TRUE, length(accessions))) {
  empty <- data.frame(
    composite_id = character(0L), sequence = character(0L),
    stringsAsFactors = FALSE
  )
  if (length(accessions) == 0L) {
    return(empty)
  }
  if (is.null(cache_dir)) {
    return(.parse_fasta_text(.fetch_fasta_batched(accessions, batch_size)))
  }

  fasta_dir <- file.path(cache_dir, "fasta")
  if (!dir.exists(fasta_dir)) dir.create(fasta_dir, recursive = TRUE)
  key <- function(a) file.path(fasta_dir, paste0(gsub("[^A-Za-z0-9]", "_", a), "_seq.rds"))
  paths <- key(accessions)

  hit <- file.exists(paths) & cacheable
  cached_rows <- lapply(which(hit), function(k) {
    tryCatch(readRDS(paths[k]), error = function(e) NULL)
  })
  cached_rows <- cached_rows[!vapply(cached_rows, is.null, logical(1L))]

  if (any(hit)) {
    message(sprintf(
      "  FASTA cache: %s of %s sequence(s) already on disk; downloading %s.",
      format(sum(hit), big.mark = ","),
      format(length(accessions), big.mark = ","),
      format(sum(!hit), big.mark = ",")
    ))
  }

  fresh <- empty
  if (any(!hit)) {
    want <- accessions[!hit]
    want_cacheable <- cacheable[!hit]
    fresh <- .parse_fasta_text(.fetch_fasta_batched(want, batch_size))
    if (nrow(fresh) > 0L) {
      # The parser returns version-STRIPPED ids; map each back to the full
      # accession it was requested under so the cache key stays versioned.
      stripped <- sub("\\.[0-9]+$", "", want)
      for (k in seq_len(nrow(fresh))) {
        j <- which(stripped == fresh$composite_id[k])
        if (length(j) == 0L || !want_cacheable[j[1L]]) next
        saveRDS(fresh[k, c("composite_id", "sequence"), drop = FALSE], key(want[j[1L]]))
      }
    }
  }

  out <- do.call(rbind, c(cached_rows, list(fresh)))
  if (is.null(out)) empty else out
}


#' Parse an INSDC lat_lon qualifier string into signed decimal degrees
#'
#' GenBank's \code{/lat_lon} qualifier uses the format
#' \code{"36.789 N 121.947 W"} (degrees, hemisphere letter, repeated for
#' longitude). Returns \code{c(lat = NA_real_, lon = NA_real_)} on any
#' missing/unparseable input -- GenBank free-text metadata is inconsistent
#' enough that this must degrade silently rather than error.
#' @noRd
.parse_lat_lon <- function(x) {
  empty <- c(lat = NA_real_, lon = NA_real_)
  if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
    return(empty)
  }

  # Extraction is validated BY REFERENCE, not by blind position: the regex
  # itself requires the first number's hemisphere letter to be N/S and the
  # second's to be E/W (the [NSns]/[EWew] character classes are part of the
  # match, not applied after the fact) -- a string that put longitude first
  # (e.g. "121.947 W 36.789 N") simply fails to match this pattern at all
  # (falls through to `empty`) rather than being silently assigned to the
  # wrong axis. This does assume GenBank's /lat_lon qualifier always pairs a
  # latitude+N/S value with a longitude+E/W value in that lat-then-lon order
  # (INSDC's own documented convention for this qualifier), not that "first
  # number = latitude" holds for an arbitrary/differently-formatted string.
  m <- regmatches(x, regexec(
    "^\\s*([0-9.]+)\\s*([NSns])\\s+([0-9.]+)\\s*([EWew])\\s*$", x
  ))[[1L]]
  if (length(m) != 5L) {
    return(empty)
  }

  lat_val <- suppressWarnings(as.numeric(m[2L]))
  lon_val <- suppressWarnings(as.numeric(m[4L]))
  if (is.na(lat_val) || is.na(lon_val)) {
    return(empty)
  }

  lat <- if (toupper(m[3L]) == "S") -lat_val else lat_val
  lon <- if (toupper(m[5L]) == "W") -lon_val else lon_val

  # Plausibility guard: a regex-matching but out-of-range value (malformed
  # GenBank free-text metadata) should degrade to NA/NA like any other
  # unparseable input, not propagate an impossible coordinate downstream.
  if (is.na(lat) || is.na(lon) || abs(lat) > 90 || abs(lon) > 180) {
    return(empty)
  }

  c(lat = lat, lon = lon)
}


#' Fetch GenBank collection location (lat_lon/country) by accession, batched
#'
#' Fetches full GBSeq XML records (\code{rettype = "gb", retmode = "xml"}) --
#' unlike \code{.fetch_summaries_batched()} (ESummary) or
#' \code{.fetch_taxonomy_map()} (taxonomy DB), this is the only record type
#' that carries the \code{source} feature's \code{lat_lon}/\code{country}
#' qualifiers. Accessions are passed directly as \code{id} (the same
#' calling convention \code{.fetch_fasta_batched()} already uses
#' successfully), so no separate search/summary round trip is needed.
#' @noRd
.fetch_locations_batched <- function(accessions, batch_size = 100L) {
  empty <- data.frame(
    composite_id = character(0L), lat = numeric(0L),
    lon = numeric(0L), country = character(0L),
    stringsAsFactors = FALSE
  )

  accessions <- unique(accessions[!is.na(accessions) & nzchar(accessions)])
  if (length(accessions) == 0L) {
    return(empty)
  }

  batches <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  res <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    result <- .retry_fetch(function() {
      xml_raw <- rentrez::entrez_fetch(
        db = "nucleotide", id = batches[[i]], rettype = "gb", retmode = "xml"
      )
      xml_doc <- xml2::read_xml(xml_raw)
      nodes <- xml2::xml_find_all(xml_doc, "//GBSeq")

      rows <- lapply(nodes, function(node) {
        acc <- xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_primary-accession"))
        quals <- xml2::xml_find_all(
          node, ".//GBFeature[GBFeature_key='source']/GBFeature_quals/GBQualifier"
        )
        qnames <- xml2::xml_text(xml2::xml_find_all(quals, "./GBQualifier_name"))
        qvals <- xml2::xml_text(xml2::xml_find_all(quals, "./GBQualifier_value"))

        lat_lon_raw <- qvals[qnames == "lat_lon"]
        country_raw <- qvals[qnames == "country"]
        ll <- .parse_lat_lon(if (length(lat_lon_raw) > 0L) lat_lon_raw[1L] else NA_character_)

        data.frame(
          composite_id = acc,
          lat = ll[["lat"]],
          lon = ll[["lon"]],
          country = if (length(country_raw) > 0L) country_raw[1L] else NA_character_,
          stringsAsFactors = FALSE
        )
      })
      # dplyr::bind_rows(), not do.call(rbind, ...) -- same reasoning as
      # .fetch_summaries_batched()/.fetch_taxonomy_map() above.
      dplyr::bind_rows(rows)
    })
    if (result$success) res[[i]] <- result$value
    Sys.sleep(.ncbi_delay())
  }

  out <- dplyr::bind_rows(res)
  # A 0-row/0-col result (no accessions resolved to any location at all)
  # lacks even the column NAMES bind_rows() would otherwise infer from real
  # data -- fall back to the pre-declared `empty` schema so callers can
  # still rely on composite_id/lat/lon/country existing.
  if (nrow(out) == 0L) empty else out
}


#' A correctly-shaped empty reference_df
#'
#' Every early return from `fetch_ncbi_reference_sequences()` must carry the
#' SAME columns as a successful one, or a caller's ordinary next step
#' (`clean_taxon_names(reference_df$species)`, joins on a rank column) fails
#' with an opaque error -- `NULL` is not a character vector -- that names
#' neither the empty result nor the reason for it. Found live when a 0-hit
#' fetch reported its own cause correctly ("No sequences found. Check taxon
#' names and barcode_term.") and the workflow then died three lines later on
#' the shape instead, burying the real message.
#' @noRd
.empty_reference_df <- function(rank_system, include_location = FALSE) {
  out <- data.frame(
    composite_id = character(0L), sequence = character(0L),
    stringsAsFactors = FALSE
  )
  for (rc in tolower(rank_system)) out[[rc]] <- character(0L)
  if (isTRUE(include_location)) {
    out$lat <- numeric(0L)
    out$lon <- numeric(0L)
    out$country <- character(0L)
  }
  out
}


#' Parse FASTA text into a data frame of composite_id + sequence
#' @noRd
.parse_fasta_text <- function(fasta_text) {
  lines <- strsplit(fasta_text, "\n")[[1L]]
  header_idx <- which(startsWith(lines, ">"))

  if (length(header_idx) == 0L) {
    return(data.frame(
      composite_id = character(0L), sequence = character(0L),
      stringsAsFactors = FALSE
    ))
  }

  seq_end_idx <- c(header_idx[-1L] - 1L, length(lines))

  ids <- character(length(header_idx))
  seqs <- character(length(header_idx))

  for (k in seq_along(header_idx)) {
    hdr <- sub("^>", "", lines[header_idx[k]])
    # Accession = first token; strip version suffix (.1, .2, etc.)
    ids[k] <- sub("\\.[0-9]+$", "", strsplit(trimws(hdr), "\\s+")[[1L]][1L])
    # A header with no sequence lines after it (a truncated FASTA -- reachable,
    # since .fetch_fasta_batched() concatenates independently-retried batches)
    # makes `start > end`, and `:` then counts DOWN, splicing an NA plus the
    # header line itself into the sequence ("NA>ACC ..."). That is not empty,
    # so it survives every downstream nchar(sequence) > 0 filter and reaches
    # the aligner as a corrupt record. Emit an empty sequence instead, which
    # the existing filters already drop.
    seqs[k] <- if (header_idx[k] + 1L > seq_end_idx[k]) {
      ""
    } else {
      seq_lines <- lines[(header_idx[k] + 1L):seq_end_idx[k]]
      paste(seq_lines[nchar(seq_lines) > 0L], collapse = "")
    }
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
#' @param max_per_species Integer or NULL (default NULL).
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
#' @param min_date Character or NULL (default; e.g. pass `"2010/01/01"` to set
#'   one). Earliest publication date for sequences. `NULL` means no lower
#'   bound -- internally resolved to the sentinel `"1900/01/01"` (predates
#'   GenBank's own founding), not left off the query entirely, so it composes
#'   safely with a supplied `max_date` alone.
#' @param max_date Character or NULL (default; e.g. pass `"2024/12/31"` to set
#'   one). Latest publication date. `NULL` means no upper bound -- internally
#'   resolved to the sentinel `"3000/12/31"`, matching `min_date`'s NULL
#'   handling above.
#' @param cache_dir Character path.
#'   Per-taxon intermediate results are cached here, enabling resumable
#'   downloads when NCBI rate-limits or the session is interrupted.
#'   Default \code{tempdir()} (clears on R restart). Set to a persistent
#'   path for cross-session caching, or \code{NULL} to disable.
#' @param ncbi_api_key Character or NULL.
#'   NCBI API key (increases rate limit from 3 to 10 requests/second).
#'   Can also be set via the `ENTREZ_KEY` environment variable.
#' @param include_location Logical (default `FALSE`).
#'   When `TRUE`, fetches each accession's full GenBank record (a real,
#'   separate NCBI round trip -- not free) and adds `lat`/`lon`/`country`
#'   columns parsed from the `source` feature's `lat_lon`/`country`
#'   qualifiers. `NA` where the record has no collection-location metadata
#'   (common for older/predicted sequences). Neither `.fetch_summaries_batched()`
#'   (ESummary) nor `.fetch_taxonomy_map()` (taxonomy DB) -- the two record
#'   types this function otherwise fetches -- carry these qualifiers, so this
#'   is a genuinely separate fetch, not a free re-parse of existing output.
#' @param keep_out_of_range Logical (default `FALSE`). When `TRUE`, sequences
#'   outside `[eff_min_len, eff_max_len]` (e.g. complete mitogenomes) are kept
#'   -- tagged via the new `in_barcode_range` output column -- instead of
#'   being dropped, capped separately per species by
#'   `max_out_of_range_per_species` so they never compete with in-range
#'   sequences for the `max_per_species`/`max_per_genus` training-set budget.
#'   Default `FALSE` preserves this function's original behavior exactly.
#'   Exists so a caller needing to check whether a species has ANY real
#'   sequence overlapping a specific genomic region (not just whether it has
#'   some barcode-length reference) can do so locally against `reference_df`,
#'   without a separate on-demand NCBI fetch -- see
#'   [restore_suppressed_candidates()]'s regional-overlap check.
#' @param max_out_of_range_per_species Integer (default `2L`). Cap on
#'   out-of-range sequences retained per species when
#'   `keep_out_of_range = TRUE`. Ignored otherwise.
#' @param max_out_of_range_len Integer (default `200000L`). Upper bound on
#'   how large a sequence can be to still be retained under
#'   `keep_out_of_range = TRUE`. Without this, a well-sequenced species'
#'   whole-genome scaffold (a real case found in production use: 111 million
#'   bp, not a mitogenome) would be retained just as readily as a real
#'   ~15-20kb mitogenome, making any later alignment against it
#'   pathologically slow for no benefit -- a scaffold that large was never a
#'   candidate for "the rescuable barcode region is embedded in this
#'   over-length submission" the way a mitogenome or chloroplast genome is.
#'   The default comfortably covers any real animal mitogenome or plant
#'   chloroplast genome (~120-160kb) with margin, while excluding genome/
#'   scaffold-scale sequences by orders of magnitude. Ignored when
#'   `keep_out_of_range = FALSE`.
#' @param count_attempts Integer (default `3L`). How many times to try each
#'   per-taxon NCBI count query before giving up on it. A count query can
#'   fail transiently, typically NCBI throttling, which `rentrez` often
#'   surfaces as the unhelpful message `"subscript out of bounds"`. Retries
#'   use exponential backoff on top of the usual inter-request delay.
#' @param on_count_failure One of `"warn"` (default) or `"error"`. What to do
#'   when a taxon's count query still fails after `count_attempts` tries.
#'   **This is not a cosmetic condition.** A failed count is excluded from the
#'   sequence budget, which sets that taxon's fetch cap to zero, so the taxon
#'   contributes NO reference sequences at all and any species-level call
#'   within it later rests on no reference data of its own. Observed for real
#'   on a PtConception 12S run: 7 taxa failed (the first 7
#'   queried, after which every remaining query succeeded), silently costing
#'   352 species-level consensus rows their own reference data, including
#'   *Medialuna californiensis*, *Zalophus californianus* and *Tursiops
#'   truncatus*. Re-issuing the identical queries afterwards succeeded for all
#'   7, confirming the failures were transient. `"warn"` keeps the run alive
#'   but reports the affected taxa by name in one consolidated warning and
#'   message, because per-taxon warnings are easy to miss in a large log (a
#'   real 17,000-line log missed all 7). Use `"error"` for an unattended
#'   production run where a
#'   silently degraded reference database is worse than a failed run.
#' @param evict_unreachable_cache Logical (default `TRUE`). When a taxon's
#'   cache file is WRITTEN, also delete that same taxon's cache files whose
#'   names the current key cannot produce for any arguments -- superseded
#'   generations left behind by an earlier key widening. This is the only
#'   part of this function that deletes anything, and it is deliberately
#'   narrow: the test is a proof, not a heuristic (see
#'   `.ref_cache_grammar()`), it is scoped to the one taxon just rewritten,
#'   it never touches a file over 5 MB, and it says what it removed. Two
#'   files that differ only in a key VALUE -- different length bounds, a
#'   different `rank_system` -- are different queries, not generations, and
#'   are never touched. Set `FALSE` to keep every historical generation.
#'   The whole-store equivalent is [taxalikely_evict_unreachable_cache()],
#'   which reports rather than deletes unless asked.
#'
#' @return A data frame (`reference_df`), carrying a `count_failures`
#'   attribute (always present, possibly zero-length) naming any taxa dropped
#'   because their count query failed -- check it with
#'   `attr(reference_df, "count_failures")` rather than reading the log.
#'   Columns:
#'   \describe{
#'     \item{`composite_id`}{NCBI accession (version suffix stripped).}
#'     \item{`sequence`}{DNA sequence string.}
#'     \item{rank columns}{One column per rank in `rank_system`
#'       (e.g., `family`, `genus`, `species`).}
#'     \item{`in_barcode_range`}{Logical. `TRUE` for sequences within
#'       `[eff_min_len, eff_max_len]`; `FALSE` for out-of-range sequences
#'       retained only when `keep_out_of_range = TRUE` (always `TRUE` when
#'       `keep_out_of_range = FALSE`, the default, since out-of-range rows
#'       are dropped entirely in that case).}
#'     \item{`slen`}{Integer. Sequence length as reported by NCBI, for
#'       reference alongside `in_barcode_range`.}
#'     \item{`lat`, `lon`, `country`}{Only when `include_location = TRUE`.
#'       Collection location parsed from GenBank's `lat_lon`/`country`
#'       qualifiers; `NA` when absent or unparseable.}
#'   }
#'   Ready for input to [build_sequence_matrix()] (which applies its own,
#'   independent length filter -- out-of-range rows kept here are excluded
#'   from training there exactly as before this parameter existed).
#'
#' @seealso [read_reference_fasta()] for loading a local FASTA file,
#'   [build_sequence_matrix()] for the next step
#'
#' @examples
#' \dontrun{
#' ref <- fetch_ncbi_reference_sequences(
#'   taxa = c("Fundulus", "Atherinops"),
#'   barcode_term = "MiFishU",
#'   max_sequences = 500
#' )
#' head(ref)
#' }
#'
#' @importFrom dplyr filter mutate group_by slice_sample ungroup n select all_of left_join distinct
#' @export
fetch_ncbi_reference_sequences <- function(taxa,
                                           barcode_term,
                                           rank_system = c("family", "genus", "species"),
                                           min_len = NULL,
                                           max_len = NULL,
                                           max_per_species = NULL,
                                           max_per_genus = NULL,
                                           priority_taxa = NULL,
                                           max_sequences = 10000L,
                                           min_per_taxon = 50L,
                                           blacklist_regex = paste0(
                                             "uncultured|environmental|predicted|",
                                             "vector|synthetic|unverified"
                                           ),
                                           min_date = NULL,
                                           max_date = NULL,
                                           cache_dir = tools::R_user_dir("TaxaLikely", "cache"),
                                           ncbi_api_key = NULL,
                                           include_location = FALSE,
                                           keep_out_of_range = FALSE,
                                           max_out_of_range_per_species = 2L,
                                           max_out_of_range_len = 200000L,
                                           count_attempts = 3L,
                                           on_count_failure = c("warn", "error"),
                                           evict_unreachable_cache = TRUE) {
  on_count_failure <- match.arg(on_count_failure)
  if (!is.logical(evict_unreachable_cache) ||
    length(evict_unreachable_cache) != 1L || is.na(evict_unreachable_cache)) {
    stop("evict_unreachable_cache must be TRUE or FALSE")
  }
  if (!is.numeric(count_attempts) || length(count_attempts) != 1L ||
    is.na(count_attempts) || count_attempts < 1L) {
    stop("count_attempts must be a single positive integer")
  }
  count_attempts <- as.integer(count_attempts)
  # --- Validate inputs --------------------------------------------------------
  if (!requireNamespace("rentrez", quietly = TRUE)) {
    stop("fetch_ncbi_reference_sequences requires the 'rentrez' package. Install with: install.packages('rentrez')")
  }
  if (!requireNamespace("xml2", quietly = TRUE)) {
    stop("fetch_ncbi_reference_sequences requires the 'xml2' package. Install with: install.packages('xml2')")
  }
  if (!is.character(taxa) || length(taxa) == 0L) {
    stop("taxa must be a non-empty character vector")
  }
  if (!is.character(barcode_term) || length(barcode_term) == 0L) {
    stop("barcode_term must be a non-empty character vector")
  }
  if (!is.character(rank_system) || length(rank_system) == 0L) {
    stop("rank_system must be a non-empty character vector (coarse to fine)")
  }
  if (!is.null(max_per_species) && (!is.numeric(max_per_species) ||
    max_per_species < 1L)) {
    stop("max_per_species must be a positive integer or NULL")
  }
  if (!is.null(max_per_genus) && (!is.numeric(max_per_genus) ||
    max_per_genus < 1L)) {
    stop("max_per_genus must be a positive integer or NULL")
  }

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

  # --- Step 0: Serve from cache BEFORE issuing any count query ---------------
  # A cached taxon issues no count query at all, so a transient count-query
  # failure cannot cost it its reference representation: an uncached,
  # network-dependent count query gating an already-cached payload is a
  # real risk -- on one real PtConception 12S run, seven genera with valid
  # cached metadata (Medialuna, Zalophus, Tursiops, Symphurus, Apodichthys,
  # Cymatogaster and Delphinus) were dropped when a transient count failure
  # set retmax_cap to 0 before the cache was ever consulted.
  #
  # Cached taxa are also excluded from `counts`, and so from the
  # max_sequences budget below. Deliberate: the budget caps what this call
  # FETCHES, and a cached taxon fetches nothing -- letting cached taxa
  # consume budget they never spend would starve the taxa actually being
  # downloaded.
  #
  # Ages are reported, not enforced. This cache has no TTL by design:
  # staleness against a remote source has no local mtime to compare against,
  # so the policy is to make age visible rather than expire silently.
  cached_meta <- vector("list", length(taxa))
  is_cached <- rep(FALSE, length(taxa))
  cache_files <- rep(NA_character_, length(taxa))
  sel_now <- .sel_params(max_per_species, max_per_genus, blacklist_regex)
  n_mismatch <- 0L

  if (!is.null(cache_dir)) {
    for (i in seq_along(taxa)) {
      cache_files[i] <- .ref_cache_file(
        cache_dir, taxa[i], barcode_term, eff_min_len, eff_max_len,
        min_date, max_date, keep_out_of_range,
        max_out_of_range_per_species, max_out_of_range_len, rank_system
      )
      if (file.exists(cache_files[i])) {
        loaded <- tryCatch(readRDS(cache_files[i]), error = function(e) NULL)
        if (!is.null(loaded)) {
          if (identical(.sel_params_status(loaded, sel_now), "mismatch")) {
            # Not verified against this call's selection settings -- either
            # recorded under different ones, or (a cache MISS either way)
            # recorded under none at all. Skipped rather than served; the
            # normal fetch path below will overwrite this same file with a
            # verified one on success.
            n_mismatch <- n_mismatch + 1L
            next
          }
          cached_meta[[i]] <- loaded
          is_cached[i] <- TRUE
        }
      }
    }
  }

  if (n_mismatch > 0L) {
    message(sprintf(
      paste0(
        "  %d cached taxon/taxa skipped (cache miss): not verified against ",
        "this call's selection settings (max_per_species / max_per_genus / ",
        "blacklist_regex) -- either recorded under different ones, or ",
        "recorded before this was tracked at all. Re-fetching those; a ",
        "successful re-fetch overwrites the file with a verified one."
      ), n_mismatch
    ))
  }

  if (any(is_cached)) {
    mtimes <- file.mtime(cache_files[is_cached])
    ages <- as.numeric(difftime(Sys.time(), mtimes, units = "days"))
    message(sprintf(
      paste0(
        "Cache: %d of %d taxon/taxa served from disk (no count query issued).\n",
        "  Location: %s\n",
        "  Age %.1f-%.1f days (oldest written %s). No TTL by policy -- to ",
        "refresh, delete those files or pass cache_dir = NULL."
      ),
      sum(is_cached), length(taxa), cache_dir,
      min(ages), max(ages), format(min(mtimes), "%Y-%m-%d")
    ))
  }

  # --- Step 1: Count-first estimation ----------------------------------------
  message("Estimating search size...")
  counts <- integer(length(taxa))
  names(counts) <- taxa

  # A count query can fail transiently (NCBI throttling or a malformed response
  # that rentrez surfaces as "subscript out of bounds"). A failure here is NOT
  # cosmetic: an NA count is excluded from the budget below and the taxon's
  # retmax_cap becomes 0, so the taxon contributes NO reference sequences at
  # all. Observed for real on a PtConception 12S run -- 7 taxa
  # (the first 7 queried, then it recovered) silently left the reference
  # database, costing 352 species-level consensus rows their own reference
  # data, including Medialuna californiensis, Zalophus californianus and
  # Tursiops truncatus. Re-issuing the identical queries afterwards succeeded
  # for all 7, confirming the failures were transient. Hence: retry with
  # backoff, and never let a survivor pass unannounced (see below).
  count_errors <- stats::setNames(
    rep(NA_character_, length(taxa)), taxa
  )

  for (i in seq_along(taxa)) {
    # Served from cache in Step 0 -- no count query, so no way to lose it to
    # a transient NCBI failure.
    if (is_cached[i]) next
    term <- .build_search_term(taxa[i], barcode_term, min_date, max_date)
    for (attempt in seq_len(count_attempts)) {
      ok <- tryCatch(
        {
          res <- rentrez::entrez_search(
            db = "nucleotide", term = term, retmax = 0L
          )
          counts[i] <- as.integer(res$count)
          count_errors[i] <- NA_character_
          TRUE
        },
        error = function(e) {
          counts[i] <<- NA_integer_
          count_errors[i] <<- conditionMessage(e)
          FALSE
        }
      )
      if (isTRUE(ok)) break
      # Back off before retrying; the last attempt is not followed by a wait.
      if (attempt < count_attempts) {
        Sys.sleep(delay * (2^attempt))
      }
    }
    Sys.sleep(delay)
  }

  # A cached taxon issued no count query, so its NA count is not a failure
  # and must not reach the count-failure warning or count_failures attribute.
  n_failed_counts <- sum(is.na(counts) & !is_cached)
  failed_taxa <- taxa[is.na(counts) & !is_cached]
  total <- sum(counts, na.rm = TRUE)
  message(sprintf("NCBI hit counts by taxon (%d total):", total))
  for (i in seq_along(taxa)) {
    message(sprintf(
      "  %s: %s", taxa[i],
      if (is_cached[i]) {
        sprintf("cached (%s row(s))", format(nrow(cached_meta[[i]]), big.mark = ","))
      } else if (is.na(counts[i])) {
        "error"
      } else {
        format(counts[i], big.mark = ",")
      }
    ))
  }

  if (total == 0L && n_failed_counts == length(taxa)) {
    stop("All NCBI count queries failed. Check your internet connection and NCBI API key.")
  }

  # One consolidated, named report -- per-taxon warnings are easy to miss in
  # a large log (seven of them went unnoticed in a real 17,000-line log), so
  # the failure mode would otherwise be silence-by-dilution, not absence of
  # a warning. State the CONSEQUENCE, not just the cause.
  if (n_failed_counts > 0L) {
    last_err <- count_errors[is.na(counts)][[1L]]
    have_key <- nzchar(Sys.getenv("ENTREZ_KEY")) || !is.null(ncbi_api_key)

    what_happened <- sprintf(
      paste0(
        "NCBI count queries failed for %d of %d taxa after %d attempt(s): %s.\n",
        "These taxa contribute ZERO reference sequences: a failed count is ",
        "excluded from the sequence budget, which sets their fetch cap to 0. ",
        "Their likelihood parameters fall back to the global values, so any ",
        "species-level call within them rests on no reference data of its own.\n",
        "Last error: %s"
      ),
      n_failed_counts, length(taxa), count_attempts,
      paste(failed_taxa, collapse = ", "), last_err
    )

    # An error is only useful if it says what to do next. Keep this list
    # ordered by what actually resolved the real occurrence.
    what_to_do <- paste0(
      "\nWHAT TO DO\n",
      "  1. Most likely transient NCBI throttling. Wait a few minutes and\n",
      "     re-run this step; in practice the affected taxa return real counts\n",
      "     on a later attempt with no change to the query.\n",
      "  2. Check NCBI is reachable and healthy:\n",
      "     https://www.ncbi.nlm.nih.gov/  and\n",
      "     rentrez::entrez_search(db = \"nucleotide\", term = \"",
      failed_taxa[[1L]], "[Organism]\", retmax = 0L)\n",
      if (have_key) {
        "  3. An API key is set, which allows 10 requests/second.\n"
      } else {
        paste0(
          "  3. NO NCBI API key detected. Without one you are limited to 3\n",
          "     requests/second, which makes throttling far more likely on a\n",
          "     large taxon list. Get a free key from your NCBI account and\n",
          "     set ENTREZ_KEY in ~/.Renviron, then restart R.\n"
        )
      },
      sprintf(
        paste0(
          "  4. Raise the retry budget: count_attempts = %d (currently %d).\n"
        ),
        max(5L, count_attempts * 2L), count_attempts
      ),
      "  5. To proceed anyway and ACCEPT a degraded reference database, set\n",
      "     on_count_failure = \"warn\". The affected taxa are then named in a\n",
      "     warning and in attr(reference_df, \"count_failures\"), so you can\n",
      "     check them rather than discover them later.\n"
    )

    if (identical(on_count_failure, "error")) {
      stop(paste0(what_happened, "\n", what_to_do), call. = FALSE)
    }
    warning(paste0(
      what_happened,
      "\nRe-running this step normally recovers them. Set ",
      "on_count_failure = \"error\" to stop instead of continuing with a ",
      "degraded reference database."
    ), call. = FALSE)
    message("\n!! ", what_happened, "\n")
  }

  # `total` counts only taxa that were actually queried. When every taxon
  # was served from cache it is legitimately 0, and returning the empty
  # reference_df here would discard a complete cached reference set -- the
  # very class of silent loss this policy work exists to stop.
  if (total == 0L && !any(is_cached)) {
    message("No sequences found. Check taxon names and barcode_term.")
    return(.with_count_failures(
      .empty_reference_df(rank_system, include_location), failed_taxa
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
        format(max_sequences, big.mark = ",")
      ))
      message(sprintf(
        "Counting %d priority species from match data...",
        length(priority_taxa)
      ))

      # Count hits for each priority species
      priority_counts <- integer(length(priority_taxa))
      names(priority_counts) <- priority_taxa

      p_batches <- split(
        priority_taxa,
        ceiling(seq_along(priority_taxa) / 40L)
      )
      for (pb in p_batches) {
        for (sp in pb) {
          tryCatch(
            {
              sp_term <- .build_search_term(sp, barcode_term, min_date, max_date)
              res <- rentrez::entrez_search(
                db = "nucleotide", term = sp_term,
                retmax = 0L
              )
              priority_counts[[sp]] <- as.integer(res$count)
            },
            error = function(e) {
              priority_counts[[sp]] <<- 0L
            }
          )
          Sys.sleep(delay)
        }
      }

      priority_budget <- sum(priority_counts, na.rm = TRUE)
      n_priority_spp <- sum(priority_counts > 0L)
      message(sprintf(
        "  Priority species: %d of %d have sequences (%s total hits)",
        n_priority_spp, length(priority_taxa),
        format(priority_budget, big.mark = ",")
      ))
    }
  }

  # Compute per-taxon caps for the broad (family/genus) searches
  retmax_cap <- stats::setNames(counts, taxa) # default: fetch everything

  if (total > max_sequences) {
    family_budget <- max(0L, max_sequences - priority_budget)
    valid <- !is.na(counts) & counts > 0L

    if (family_budget > 0L) {
      guarantee <- pmin(counts[valid], as.integer(min_per_taxon))
      remaining <- family_budget - sum(guarantee)

      if (remaining > 0L) {
        excess <- pmax(counts[valid] - guarantee, 0L)
        total_excess <- sum(excess)
        if (total_excess > 0L) {
          bonus <- floor(excess / total_excess * remaining)
        } else {
          bonus <- rep(0L, sum(valid))
        }
        retmax_cap[valid] <- guarantee + bonus
      } else {
        # Budget exhausted by guarantees; give each the minimum possible
        retmax_cap[valid] <- pmin(
          counts[valid],
          pmax(1L, floor(family_budget / sum(valid)))
        )
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
      format(sum(retmax_cap, na.rm = TRUE), big.mark = ",")
    ))
  }

  # --- Step 2a: Fetch priority species first ---------------------------------
  priority_meta <- list()

  if (length(priority_counts) > 0L && priority_budget > 0L) {
    message("\nFetching priority species sequences...")
    for (sp in names(priority_counts)) {
      if (priority_counts[[sp]] == 0L) next

      # Check cache. The key (and the reasoning behind every component of
      # it) now lives in .ref_cache_file(); this path differs from the broad
      # search only by its "priority_" prefix.
      #
      # NOTE: unlike the broad path, the priority path still counts before
      # it checks the cache. It is only reachable when total > max_sequences
      # AND priority_taxa was supplied, which no production workflow does,
      # so the Step 0 cache-before-count reordering was not extended here
      # rather than restructuring a budget-driven loop that nothing
      # exercises.
      p_cache_file <- .ref_cache_file(
        cache_dir, sp, barcode_term, eff_min_len, eff_max_len,
        min_date, max_date, keep_out_of_range,
        max_out_of_range_per_species, max_out_of_range_len, rank_system,
        prefix = "priority_"
      )
      if (!is.null(p_cache_file)) {
        if (file.exists(p_cache_file)) {
          message(sprintf("  %s: loading from cache", sp))
          p_reloaded <- readRDS(p_cache_file)
          if (!identical(.sel_params_status(p_reloaded, sel_now), "mismatch")) {
            priority_meta[[sp]] <- p_reloaded
            next
          }
        }
      }

      message(sprintf(
        "  %s: fetching %s summaries...",
        sp, format(priority_counts[[sp]], big.mark = ",")
      ))
      tryCatch(
        {
          sp_term <- .build_search_term(sp, barcode_term, min_date, max_date)
          search_obj <- rentrez::entrez_search(
            db = "nucleotide", term = sp_term,
            retmax = min(priority_counts[[sp]], 9999L), use_history = TRUE
          )
          meta <- .fetch_summaries_batched(search_obj)
          if (!is.null(meta) && nrow(meta) > 0L) {
            priority_meta[[sp]] <- meta
            if (!is.null(p_cache_file)) {
              attr(meta, "sel_params") <- sel_now
              saveRDS(meta, p_cache_file)
              if (isTRUE(evict_unreachable_cache)) {
                .ref_cache_evict(
                  cache_dir, .ref_cache_stem(sp, barcode_term, prefix = "priority_")
                )
              }
            }
          }
        },
        error = function(e) {
          warning(sprintf(
            "Priority fetch failed for '%s': %s", sp,
            conditionMessage(e)
          ), call. = FALSE)
        }
      )
      Sys.sleep(delay)
    }
  }

  # --- Step 2b: Broader family/genus fetch ------------------------------------
  message("\nFetching broader taxonomic context...")
  all_meta <- cached_meta # pre-populated by the Step 0 cache pass

  for (i in seq_along(taxa)) {
    if (is.na(counts[i]) || counts[i] == 0L) next

    # Cache path. The Step 0 pass above already served every existing hit,
    # so this is normally a miss; it is kept for the case where the file
    # appeared mid-run. The key itself lives in .ref_cache_file().
    cache_file <- if (!is.na(cache_files[i])) {
      cache_files[i]
    } else {
      .ref_cache_file(
        cache_dir, taxa[i], barcode_term, eff_min_len, eff_max_len,
        min_date, max_date, keep_out_of_range,
        max_out_of_range_per_species, max_out_of_range_len, rank_system
      )
    }
    if (!is.null(cache_file)) {
      if (file.exists(cache_file)) {
        reloaded <- readRDS(cache_file)
        if (!identical(.sel_params_status(reloaded, sel_now), "mismatch")) {
          message(sprintf("  %s: loading from cache", taxa[i]))
          all_meta[[i]] <- reloaded
          next
        }
      }
    }

    fetch_n <- retmax_cap[[taxa[i]]]
    if (is.na(fetch_n) || fetch_n == 0L) next

    # Wrap entire per-taxon fetch in tryCatch so NCBI rate-limit or parse
    # errors skip one taxon instead of crashing the whole run.
    tryCatch(
      {
        capped_msg <- if (fetch_n < counts[i]) {
          sprintf(" (capped from %s)", format(counts[i], big.mark = ","))
        } else {
          ""
        }
        message(sprintf(
          "  %s: fetching %s summaries%s...",
          taxa[i], format(fetch_n, big.mark = ","), capped_msg
        ))

        term <- .build_search_term(taxa[i], barcode_term, min_date, max_date)
        search_obj <- rentrez::entrez_search(
          db = "nucleotide", term = term,
          retmax = min(fetch_n, 9999L), use_history = TRUE
        )

        # Summaries (lightweight: accession, taxid, length, title)
        meta <- .fetch_summaries_batched(search_obj)

        if (is.null(meta) || nrow(meta) == 0L) {
          warning(sprintf("No summaries retrieved for '%s'", taxa[i]),
            call. = FALSE
          )
          next
        }

        # Length filter (on summary metadata, before downloading sequences).
        # keep_out_of_range = TRUE retains out-of-range (e.g. mitogenome-length)
        # sequences too, tagged via in_barcode_range, instead of dropping them --
        # needed so a regional-overlap check (e.g. restore_suppressed_
        # candidates()'s coverage check) has real reference sequence content to
        # compare against for species whose only NCBI submission is over-length,
        # without a separate on-demand fetch. Capped separately below
        # (max_out_of_range_per_species) so out-of-range sequences never compete
        # with in-range ones for the max_per_species training-set budget.
        meta$in_barcode_range <- !is.na(meta$slen) &
          meta$slen >= eff_min_len &
          meta$slen <= eff_max_len
        meta <- if (keep_out_of_range) {
          # max_out_of_range_len bounds what "out-of-range but still worth
          # keeping" means -- without this, a well-sequenced species' whole-
          # genome scaffold (real case found in production use: 111 million bp,
          # not a mitogenome) gets retained just as readily as a real ~16-20kb
          # mitogenome, making any later alignment against it pathologically
          # slow for no benefit (a scaffold that large was never a candidate
          # for "the rescuable region is embedded in this over-length
          # submission" the way a mitogenome or chloroplast genome is).
          # Default 200,000bp comfortably covers any real animal mitogenome
          # (~15-20kb) or plant chloroplast genome (~120-160kb) with margin,
          # while excluding genome/scaffold-scale sequences (typically
          # millions+ bp) by orders of magnitude.
          meta[!is.na(meta$slen) & meta$slen <= max_out_of_range_len, , drop = FALSE]
        } else {
          meta[meta$in_barcode_range, , drop = FALSE]
        }

        # Blacklist filter
        if (!is.null(blacklist_regex) && nchar(blacklist_regex) > 0L) {
          meta <- meta[!grepl(blacklist_regex, meta$title, ignore.case = TRUE), ,
            drop = FALSE
          ]
        }

        if (nrow(meta) == 0L) {
          message(sprintf("  %s: no sequences passed filters", taxa[i]))
          next
        }

        # Taxonomy bridge: taxid -> full lineage
        unique_taxids <- unique(meta$taxid)
        unique_taxids <- unique_taxids[!is.na(unique_taxids) &
          nchar(unique_taxids) > 0L]

        message(sprintf(
          "  %s: resolving taxonomy for %d unique taxids...",
          taxa[i], length(unique_taxids)
        ))
        tax_map <- .fetch_taxonomy_map(unique_taxids, tolower(rank_system))

        if (is.null(tax_map) || nrow(tax_map) == 0L) {
          warning(sprintf("Taxonomy resolution failed for '%s'", taxa[i]),
            call. = FALSE
          )
          next
        }

        meta <- merge(meta, tax_map, by = "taxid", all.x = TRUE)

        # Drop rows with missing finest-rank taxonomy
        finest_rank <- tolower(rank_system[length(rank_system)])
        meta <- meta[!is.na(meta[[finest_rank]]), , drop = FALSE]

        # Filter to valid species names (reuse coverage.R helper pattern)
        if (finest_rank == "species") {
          meta <- meta[TaxaTools::is_plausible_binomial(meta$species), ,
            drop = FALSE
          ]
        }

        if (nrow(meta) == 0L) {
          message(sprintf("  %s: no sequences with valid taxonomy", taxa[i]))
          next
        }

        # Stratified downsampling. in-range and out-of-range rows are sampled
        # SEPARATELY so out-of-range sequences (capped by
        # max_out_of_range_per_species below) never displace in-range
        # training-set candidates within the max_per_species/max_per_genus
        # budgets -- those budgets keep their existing pre-keep_out_of_range
        # meaning entirely.
        in_range_meta <- meta[meta$in_barcode_range, , drop = FALSE]
        out_range_meta <- meta[!meta$in_barcode_range, , drop = FALSE]

        if (!is.null(max_per_species) && finest_rank == "species") {
          in_range_meta <- dplyr::group_by(in_range_meta, species)
          in_range_meta <- dplyr::slice_sample(in_range_meta, n = max_per_species)
          in_range_meta <- dplyr::ungroup(in_range_meta)
        }
        if (!is.null(max_per_genus) && "genus" %in% tolower(rank_system)) {
          in_range_meta <- dplyr::group_by(in_range_meta, genus)
          in_range_meta <- dplyr::slice_sample(in_range_meta, n = max_per_genus)
          in_range_meta <- dplyr::ungroup(in_range_meta)
        }
        if (nrow(out_range_meta) > 0L && finest_rank == "species") {
          out_range_meta <- dplyr::group_by(out_range_meta, species)
          out_range_meta <- dplyr::slice_sample(out_range_meta, n = max_out_of_range_per_species)
          out_range_meta <- dplyr::ungroup(out_range_meta)
        }

        meta <- dplyr::bind_rows(in_range_meta, out_range_meta)

        message(sprintf(
          "  %s: %d sequences after filtering/downsampling%s",
          taxa[i], nrow(meta),
          if (keep_out_of_range) {
            sprintf(
              " (%d in-range, %d out-of-range)",
              sum(meta$in_barcode_range), sum(!meta$in_barcode_range)
            )
          } else {
            ""
          }
        ))

        all_meta[[i]] <- meta

        # Cache intermediate result
        if (!is.null(cache_file)) {
          # Record the selection settings this object was built under, so a
          # later call with different ones re-fetches instead of silently
          # inheriting an under-filled set. See .sel_params().
          attr(meta, "sel_params") <- sel_now
          saveRDS(meta, cache_file)
          if (isTRUE(evict_unreachable_cache)) {
            .ref_cache_evict(cache_dir, .ref_cache_stem(taxa[i], barcode_term))
          }
        }
      },
      error = function(e) {
        warning(sprintf(
          "fetch_ncbi_reference_sequences: '%s' failed (%s). Skipping this taxon.",
          taxa[i], conditionMessage(e)
        ), call. = FALSE)
      }
    )
  }

  # --- Combine priority + family metadata -------------------------------------
  # Priority meta needs the same length/blacklist/taxonomy filtering applied
  # to family results. Process priority meta through the same pipeline.
  if (length(priority_meta) > 0L) {
    # dplyr::bind_rows(), not do.call(rbind, ...) -- same real-data column-
    # mismatch risk as the per-taxon combining above.
    priority_combined <- dplyr::bind_rows(priority_meta)
    if (!is.null(priority_combined) && nrow(priority_combined) > 0L) {
      # Length filter (see the family/genus path's identical comment above for
      # why keep_out_of_range retains out-of-range rows, tagged, instead of
      # dropping them)
      priority_combined$in_barcode_range <- !is.na(priority_combined$slen) &
        priority_combined$slen >= eff_min_len &
        priority_combined$slen <= eff_max_len
      priority_combined <- if (keep_out_of_range) {
        # max_out_of_range_len bound -- see the family/genus path's identical
        # comment above for why this is needed.
        priority_combined[!is.na(priority_combined$slen) &
          priority_combined$slen <= max_out_of_range_len, , drop = FALSE]
      } else {
        priority_combined[priority_combined$in_barcode_range, , drop = FALSE]
      }
      # Blacklist filter
      if (!is.null(blacklist_regex) && nchar(blacklist_regex) > 0L) {
        priority_combined <- priority_combined[
          !grepl(blacklist_regex, priority_combined$title, ignore.case = TRUE), ,
          drop = FALSE
        ]
      }
      if (nrow(priority_combined) > 0L) {
        # Taxonomy resolution
        p_taxids <- unique(priority_combined$taxid)
        p_taxids <- p_taxids[!is.na(p_taxids) & nchar(p_taxids) > 0L]
        if (length(p_taxids) > 0L) {
          message(sprintf(
            "Resolving taxonomy for %d priority taxids...",
            length(p_taxids)
          ))
          p_tax_map <- .fetch_taxonomy_map(p_taxids, tolower(rank_system))
          if (!is.null(p_tax_map) && nrow(p_tax_map) > 0L) {
            priority_combined <- merge(priority_combined, p_tax_map,
              by = "taxid", all.x = TRUE
            )
            finest_rank <- tolower(rank_system[length(rank_system)])
            priority_combined <- priority_combined[
              !is.na(priority_combined[[finest_rank]]), ,
              drop = FALSE
            ]
            if (finest_rank == "species") {
              priority_combined <- priority_combined[
                TaxaTools::is_plausible_binomial(priority_combined$species), ,
                drop = FALSE
              ]
            }
            # Cap out-of-range rows per species (priority species otherwise
            # get their full allocation, uncapped, by design -- but an
            # unbounded number of mitogenome-length submissions per species
            # is still worth bounding for the same reason as the family/
            # genus path above).
            if (keep_out_of_range && finest_rank == "species" &&
              nrow(priority_combined) > 0L) {
              p_in_range <- priority_combined[priority_combined$in_barcode_range, , drop = FALSE]
              p_out_range <- priority_combined[!priority_combined$in_barcode_range, , drop = FALSE]
              if (nrow(p_out_range) > 0L) {
                p_out_range <- dplyr::group_by(p_out_range, species)
                p_out_range <- dplyr::slice_sample(p_out_range, n = max_out_of_range_per_species)
                p_out_range <- dplyr::ungroup(p_out_range)
              }
              priority_combined <- dplyr::bind_rows(p_in_range, p_out_range)
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
              tolower(rank_system[length(rank_system)])
            ]])
          ))
        }
      }
    } else {
      priority_combined <- NULL
    }
  } else {
    priority_combined <- NULL
  }

  # dplyr::bind_rows(), not do.call(rbind, ...) -- this is the real crash
  # site confirmed against a live ~1300-genus PtConception 18S fetch
  # ("Error in rbind(deparse.level, ...) : numbers of columns of arguments
  # do not match"): all_meta's per-genus data frames each go through their
  # own independent taxonomy-merge/filter sequence,
  # and real NCBI taxonomy XML is not perfectly uniform across genera (see
  # .fetch_taxonomy_map()'s own note above) -- any one genus with a
  # slightly different resolved column set was enough to hard-error the
  # WHOLE fetch, discarding every other genus's already-completed work.
  family_meta <- dplyr::bind_rows(all_meta)

  # Merge: priority first, then family (deduplicate by accession). Same
  # dplyr::bind_rows() fix -- priority_combined and family_meta are built by
  # separately-written code paths that aren't guaranteed to produce
  # byte-identical column sets even when both are conceptually "the same
  # shape."
  meta_parts <- Filter(
    Negate(is.null),
    list(priority_combined, family_meta)
  )
  combined_meta <- if (length(meta_parts) > 0L) dplyr::bind_rows(meta_parts) else NULL

  if (is.null(combined_meta) || nrow(combined_meta) == 0L) {
    message("No sequences passed all filters across all taxa.")
    return(.with_count_failures(
      .empty_reference_df(rank_system, include_location), failed_taxa
    ))
  }

  # Deduplicate by accession (priority sequences take precedence)
  combined_meta <- combined_meta[!duplicated(combined_meta$acc), , drop = FALSE]
  message(sprintf("\nFetching FASTA for %d sequences...", nrow(combined_meta)))

  # --- Step 3: Fetch FASTA sequences ------------------------------------------
  # Key (and request) the versioned accession where the metadata carries one,
  # so a revised GenBank record is a cache MISS rather than a silent hit on
  # the superseded sequence. A record whose metadata has no acc_version has
  # no version to offer and cannot see a revision anyway -- it is a cache
  # MISS unconditionally (see .fasta_cache_keys()/.fetch_fasta_cached()):
  # downloaded fresh every time, never read from or written to the fasta/
  # store, until a re-fetch of its metadata records a real version.
  fasta_keys <- .fasta_cache_keys(combined_meta)
  n_unversioned <- attr(fasta_keys, "n_unversioned")
  if (!is.null(n_unversioned) && n_unversioned > 0L) {
    message(sprintf(
      paste0(
        "  FASTA cache: %s of %s accession(s) have no recorded version and ",
        "so cannot be cached; downloaded fresh (skipped as a cache miss)."
      ),
      format(n_unversioned, big.mark = ","),
      format(length(fasta_keys), big.mark = ",")
    ))
  }
  fasta_df <- .fetch_fasta_cached(fasta_keys, cache_dir, cacheable = attr(fasta_keys, "cacheable"))

  if (nrow(fasta_df) == 0L) {
    warning("FASTA download returned no sequences")
    return(.with_count_failures(
      .empty_reference_df(rank_system, include_location), failed_taxa
    ))
  }

  # Strip version suffix from accessions in metadata for joining
  combined_meta$composite_id <- sub("\\.[0-9]+$", "", combined_meta$acc)

  # Join sequences to taxonomy. in_barcode_range/slen carried through so
  # downstream consumers (e.g. a regional-overlap check) can distinguish
  # properly-sized training-eligible sequences from out-of-range ones kept
  # only when keep_out_of_range = TRUE.
  rank_cols <- tolower(rank_system)
  keep_cols <- c("composite_id", rank_cols, "in_barcode_range", "slen")
  # create_date is only included when present -- a cache written before this
  # column existed (keyed identically otherwise: taxon/barcode/length/date
  # unchanged) would lack it, and this keeps that stale-cache case a graceful
  # NA-column omission rather than a hard "undefined columns selected" crash.
  if ("create_date" %in% names(combined_meta)) keep_cols <- c(keep_cols, "create_date")
  lookup <- combined_meta[!duplicated(combined_meta$composite_id), keep_cols,
    drop = FALSE
  ]

  reference_df <- merge(fasta_df, lookup, by = "composite_id", all.x = FALSE)
  reference_df <- reference_df[!is.na(reference_df$sequence) &
    nchar(reference_df$sequence) > 0L, , drop = FALSE]

  # --- Optional: collection location (lat/lon/country) -----------------------
  if (include_location) {
    message(sprintf(
      "Fetching location metadata for %d accessions...",
      length(unique(combined_meta$acc))
    ))
    loc_df <- .fetch_locations_batched(combined_meta$acc)
    if (nrow(loc_df) > 0L) {
      reference_df <- merge(reference_df, loc_df, by = "composite_id", all.x = TRUE)
    } else {
      reference_df$lat <- NA_real_
      reference_df$lon <- NA_real_
      reference_df$country <- NA_character_
    }
  }

  finest_rank <- tolower(rank_system[length(rank_system)])
  message(sprintf(
    "Done. reference_df: %d sequences, %d unique %s",
    nrow(reference_df),
    dplyr::n_distinct(reference_df[[finest_rank]]),
    finest_rank
  ))
  .with_count_failures(reference_df, failed_taxa)
}


#' Attach the count-failure audit trail to a reference table
#'
#' Records which taxa were dropped because their NCBI count query failed, so a
#' caller can check programmatically rather than reading the log.
#'
#' @param x A reference data frame.
#' @param failed_taxa Character vector of taxa whose count query failed.
#' @return `x`, with a `count_failures` attribute (always present, possibly
#'   a zero-length character vector).
#' @noRd
.with_count_failures <- function(x, failed_taxa) {
  attr(x, "count_failures") <- as.character(failed_taxa)
  x
}


# ==============================================================================
# BOLD Systems v5 Data Portal API (reference-fetch analog of NCBI)
# ==============================================================================
# BOLD migrated to a new "v5" Data Portal API in 2024; the old v3/v4 endpoints
# the (now CRAN-archived) `bold` R package targets are permanently retired --
# confirmed directly (bold_seqspec()/bold_identify() both return
# a "BOLD Public Offline" page against the old API). This talks to the new,
# live, documented API (https://portal.boldsystems.org/openapi.json) directly
# via httr2, matching how this ecosystem already talks to NCBI (rentrez) and
# Xeno-canto (raw httr2) -- no `bold` package dependency needed at all.

#' BOLD's v5 Data Portal API base URL
#' @noRd
.bold_api_base <- "https://portal.boldsystems.org/api"

#' Resolve a free-text taxon name into a formal BOLD query triplet
#'
#' Calls \code{query/preprocessor}. Returns a semicolon-joined string of
#' resolved \code{scope:subscope:value} triplets (usually just one, e.g.
#' \code{"tax:species:Melanogrammus aeglefinus"}), or \code{NA_character_} if
#' the taxon can't be resolved.
#' @noRd
.bold_resolve_taxon <- function(taxon) {
  req <- httr2::request(.bold_api_base) |>
    httr2::req_url_path_append("query", "preprocessor") |>
    httr2::req_url_query(query = taxon) |>
    httr2::req_error(is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp) || httr2::resp_status(resp) != 200L) {
    return(NA_character_)
  }

  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  terms <- body[["successful_terms"]]
  if (is.null(terms) || length(terms) == 0L) {
    return(NA_character_)
  }

  matched <- vapply(terms, function(x) {
    v <- x[["matched"]]
    if (is.null(v)) NA_character_ else v
  }, character(1L))
  matched <- matched[!is.na(matched) & nzchar(matched)]
  if (length(matched) == 0L) {
    return(NA_character_)
  }

  paste(matched, collapse = ";")
}

#' Submit a resolved BOLD query triplet and return its query_id
#' @noRd
.bold_submit_query <- function(triplet, extent = "full") {
  req <- httr2::request(.bold_api_base) |>
    httr2::req_url_path_append("query") |>
    httr2::req_url_query(query = triplet, extent = extent) |>
    httr2::req_error(is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp) || httr2::resp_status(resp) != 200L) {
    return(NA_character_)
  }

  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  qid <- body[["query_id"]]
  if (is.null(qid)) NA_character_ else qid
}

#' Download BOLD records for a resolved query_id as a data frame
#'
#' Requests TSV (not JSON) -- BOLD's download endpoint returns full records
#' in one response regardless of format (it "ignores the query extent to
#' always download the full extent" per its own API docs), and TSV parses
#' with base R's \code{read.delim()} without a new JSON dependency, matching
#' this ecosystem's existing preference (NCBI ESummary/FASTA are handled the
#' same way).
#' @noRd
.bold_fetch_documents <- function(query_id) {
  req <- httr2::request(.bold_api_base) |>
    httr2::req_url_path_append("documents", query_id, "download") |>
    httr2::req_url_query(format = "tsv") |>
    httr2::req_error(is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp) || httr2::resp_status(resp) != 200L) {
    return(NULL)
  }

  txt <- tryCatch(httr2::resp_body_string(resp), error = function(e) NULL)
  if (is.null(txt) || !nzchar(trimws(txt))) {
    return(NULL)
  }

  tryCatch(
    utils::read.delim(
      text = txt, sep = "\t", quote = "", na.strings = "",
      stringsAsFactors = FALSE, check.names = FALSE
    ),
    error = function(e) NULL
  )
}

#' Parse BOLD's bracketed \code{coord} field (\code{"[lat, lon]"}) into
#' signed decimal degrees
#'
#' Confirmed format directly against real populated records (e.g.
#' \emph{Danaus plexippus} specimens) -- GenBank-mined BOLD records
#' (the majority) have \code{coord = NA}; field-vouchered specimens carry
#' real values in this bracketed-array style.
#' @noRd
.parse_bold_coord <- function(x) {
  empty <- c(lat = NA_real_, lon = NA_real_)
  if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
    return(empty)
  }
  x <- gsub("[][]", "", x)
  parts <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  if (length(parts) != 2L) {
    return(empty)
  }
  vals <- suppressWarnings(as.numeric(parts))
  if (anyNA(vals)) {
    return(empty)
  }
  c(lat = vals[1L], lon = vals[2L])
}


#' Fetch reference sequences from BOLD Systems for model building
#'
#' Searches BOLD's v5 Data Portal API by taxon name and returns a
#' `reference_df` ready for [build_sequence_matrix()] -- the BOLD analog of
#' [fetch_ncbi_reference_sequences()].
#'
#' @details
#' Talks directly to BOLD's live v5 Data Portal API
#' (\url{https://portal.boldsystems.org/api}) via a 3-stage flow:
#' \code{query/preprocessor} resolves a taxon name into a formal query
#' triplet, \code{query} submits it and returns a \code{query_id}, and
#' \code{documents/{query_id}/download} returns the matching records. No API
#' key required. Confirmed live and documented directly against BOLD's own
#' OpenAPI spec (\url{https://portal.boldsystems.org/openapi.json}) --
#' this does NOT wrap the \code{bold} R package, whose
#' \code{bold_seqspec()}/\code{bold_identify()} target BOLD's now-retired
#' v3/v4 API and no longer work.
#'
#' \strong{No server-side marker/locus filter exists.} BOLD's query API only
#' supports \code{tax}/\code{geo}/\code{ids}/\code{bin}/\code{recordsetcode}
#' scopes -- there is no marker/gene scope the way NCBI's \code{[GENE]} field
#' tag provides via [fetch_ncbi_reference_sequences()]. \code{barcode_term}
#' is therefore applied as a client-side filter on the returned
#' \code{marker_code} field (e.g. \code{"COI-5P"}, \code{"COI-3P"}) after
#' download, not as part of the query itself -- every record for the taxon
#' is fetched regardless of marker.
#'
#' \strong{Location comes free, like BOLD's own `coord`/`country/ocean`
#' fields}: no separate round trip is needed the way NCBI requires one
#' (\code{include_location} on [fetch_ncbi_reference_sequences()] triggers a
#' real second fetch) -- BOLD's query already returns these fields, so this
#' parameter just controls whether to keep or drop the columns.
#'
#' @param taxa Character vector of taxon names to search. Each is resolved
#'   and queried separately; results are combined and de-duplicated by
#'   \code{processid}.
#' @param barcode_term Character vector of BOLD marker codes to keep (e.g.
#'   \code{"COI-5P"}), matched against the returned \code{marker_code}
#'   column. \code{NULL} (default) keeps every marker returned.
#' @param rank_system Character vector of taxonomy ranks, coarse to fine
#'   (default \code{c("family", "genus", "species")}). Resolved from BOLD's
#'   own taxonomy columns (\code{kingdom}, \code{phylum}, \code{class},
#'   \code{order}, \code{family}, \code{subfamily}, \code{genus},
#'   \code{species}, \code{subspecies} -- confirmed against a live query).
#' @param max_per_species Integer or \code{NULL} (default \code{NULL}).
#'   Maximum sequences per species (stratified downsampling), matching
#'   [fetch_ncbi_reference_sequences()]'s convention. Requires
#'   \code{"species"} to be in \code{rank_system}.
#' @param include_location Logical (default \code{TRUE}). Keep the
#'   \code{lat}/\code{lon}/\code{country} columns parsed from BOLD's own
#'   \code{coord}/\code{country/ocean} fields. \code{NA} where BOLD has no
#'   collection-location metadata (common -- most BOLD records are
#'   GenBank-mined and carry no field-collection coordinates).
#'
#' @return A data frame (`reference_df`) with columns:
#'   \describe{
#'     \item{`composite_id`}{BOLD `processid`.}
#'     \item{`sequence`}{DNA sequence string (BOLD's `nuc` field).}
#'     \item{rank columns}{One column per rank in `rank_system`.}
#'     \item{`lat`, `lon`, `country`}{Only when `include_location = TRUE`.}
#'   }
#'   Ready for input to [build_sequence_matrix()].
#'
#' @seealso [fetch_ncbi_reference_sequences()] for the NCBI equivalent,
#'   [build_sequence_matrix()] for the next step
#'
#' @examples
#' \dontrun{
#' ref <- fetch_bold_reference_sequences(
#'   taxa = c("Fundulus", "Atherinops"),
#'   barcode_term = "COI-5P"
#' )
#' head(ref)
#' }
#'
#' @importFrom dplyr group_by slice_sample ungroup n_distinct bind_rows
#' @export
fetch_bold_reference_sequences <- function(taxa,
                                           barcode_term = NULL,
                                           rank_system = c("family", "genus", "species"),
                                           max_per_species = NULL,
                                           include_location = TRUE) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("fetch_bold_reference_sequences requires the 'httr2' package. Install with: install.packages('httr2')")
  }
  if (!is.character(taxa) || length(taxa) == 0L) {
    stop("taxa must be a non-empty character vector")
  }
  if (!is.character(rank_system) || length(rank_system) == 0L) {
    stop("rank_system must be a non-empty character vector (coarse to fine)")
  }
  if (!is.null(barcode_term) && !is.character(barcode_term)) {
    stop("barcode_term must be a character vector or NULL")
  }
  if (!is.null(max_per_species) && (!is.numeric(max_per_species) || max_per_species < 1L)) {
    stop("max_per_species must be a positive integer or NULL")
  }

  message("Querying BOLD Systems v5 Data Portal API...")
  all_records <- vector("list", length(taxa))

  for (i in seq_along(taxa)) {
    triplet <- .bold_resolve_taxon(taxa[i])
    if (is.na(triplet)) {
      warning(sprintf(
        "fetch_bold_reference_sequences: '%s' could not be resolved by BOLD. Skipping.",
        taxa[i]
      ), call. = FALSE)
      next
    }

    query_id <- .bold_submit_query(triplet)
    if (is.na(query_id)) {
      warning(sprintf(
        "fetch_bold_reference_sequences: query submission failed for '%s'. Skipping.",
        taxa[i]
      ), call. = FALSE)
      next
    }

    docs <- .bold_fetch_documents(query_id)
    if (is.null(docs) || nrow(docs) == 0L) {
      message(sprintf("  %s: no records returned", taxa[i]))
      next
    }

    message(sprintf("  %s: %d record(s)", taxa[i], nrow(docs)))
    all_records[[i]] <- docs
  }

  # dplyr::bind_rows(), not rbind() -- BOLD's per-query TSV column set can
  # differ across taxa (confirmed live: some optional/flattened
  # columns only appear when populated for that result set), so a plain
  # rbind() errors on mismatched column counts.
  non_null_records <- Filter(Negate(is.null), all_records)
  combined <- if (length(non_null_records) > 0L) {
    as.data.frame(dplyr::bind_rows(non_null_records))
  } else {
    NULL
  }
  # Same shape a successful return has -- see .empty_reference_df()'s own
  # documentation for why: a bare 2-column frame makes a caller's ordinary
  # next step (clean_taxon_names(reference_df$species), a join on a rank
  # column) fail on NULL, burying this function's own correct explanation of
  # why the result was empty.
  empty_out <- .empty_reference_df(rank_system, include_location)

  if (is.null(combined) || nrow(combined) == 0L) {
    message("No records found for any taxon.")
    return(empty_out)
  }

  combined <- combined[!duplicated(combined$processid), , drop = FALSE]

  if (!is.null(barcode_term)) {
    combined <- combined[!is.na(combined$marker_code) &
      combined$marker_code %in% barcode_term, , drop = FALSE]
    if (nrow(combined) == 0L) {
      message("No records matched the requested barcode_term after filtering.")
      return(empty_out)
    }
  }

  combined <- combined[!is.na(combined$nuc) & nzchar(combined$nuc), , drop = FALSE]
  if (nrow(combined) == 0L) {
    message("No records with a usable sequence.")
    return(empty_out)
  }

  if (!is.null(max_per_species) && "species" %in% rank_system &&
    "species" %in% names(combined)) {
    combined <- dplyr::group_by(combined, species)
    combined <- dplyr::slice_sample(combined, n = max_per_species)
    combined <- dplyr::ungroup(combined)
  }

  out <- data.frame(
    composite_id = combined$processid,
    sequence = combined$nuc,
    stringsAsFactors = FALSE
  )

  for (rc in tolower(rank_system)) {
    out[[rc]] <- if (rc %in% names(combined)) combined[[rc]] else NA_character_
  }

  if (include_location) {
    if ("coord" %in% names(combined)) {
      coord_mat <- t(vapply(combined$coord, .parse_bold_coord, numeric(2L)))
      out$lat <- unname(coord_mat[, 1L])
      out$lon <- unname(coord_mat[, 2L])
    } else {
      out$lat <- NA_real_
      out$lon <- NA_real_
    }
    out$country <- if ("country/ocean" %in% names(combined)) combined[["country/ocean"]] else NA_character_
  }

  rownames(out) <- NULL
  finest_rank <- tolower(rank_system[length(rank_system)])
  message(sprintf(
    "Done. reference_df: %d sequences, %d unique %s",
    nrow(out), dplyr::n_distinct(out[[finest_rank]]), finest_rank
  ))
  out
}


# --- Internal helpers for taxonomy_file parsing in read_reference_fasta() ----

#' Standard 7-level hierarchy used for positional taxonomy-string parsing
#'
#' Same values as \code{TaxaTools::standard_ranks} (kept as its own named
#' constant, not just an inline reference, because the CRABS positional
#' taxonomy-string format this is used to parse is specifically defined
#' against this 7-level order -- see the "does not line up with" note on
#' \code{.parse_tax_string()} below).
#' @noRd
.crabs_std_hierarchy <- TaxaTools::standard_ranks

#' PR2's fixed 9-level positional hierarchy
#'
#' Confirmed directly against a real PR2 v5.1.1 release file
#' (\code{pr2_version_5.1.1_SSU_mothur.tax.gz}, 240,201 records): every single
#' record uses exactly this 9-level positional order, with no missing levels
#' and no prefix codes -- e.g.
#' \code{Eukaryota;TSAR;Alveolata;Dinoflagellata;Dinophyceae;Peridiniales;Kryptoperidiniaceae;Unruhdinium;Unruhdinium_kevei}.
#' This does not line up with \code{.crabs_std_hierarchy} (7 levels,
#' kingdom-first) either in count or in rank names -- PR2's own
#' \code{supergroup}/\code{division}/\code{subdivision} concepts (protist
#' taxonomy) have no equivalent there, so PR2 gets its own hierarchy constant
#' rather than bending the shared one every other positional source relies on.
#' Two real quirks confirmed in the same file, deliberately NOT auto-corrected
#' here (this parser stays a faithful structural splitter, same as it is for
#' every other source): (1) plastid-derived sequences suffix every level with
#' \code{:plas} (e.g. \code{Eukaryota:plas}) -- collapsing that would erase a
#' real, scientifically meaningful distinction (plastid ancestry vs. nuclear
#' genome), so it is preserved as-is in the parsed value; (2) the
#' \code{species} level is underscore-joined (\code{Unruhdinium_kevei}), not
#' space-separated, and many "species" values are unresolved placeholder
#' labels (e.g. \code{Rozellomycota_XXX_sp.}) rather than real binomials --
#' callers wanting a clean binomial should post-process, this parser does not
#' guess which underscore-joined values are real names.
#' @noRd
.pr2_hierarchy <- c(
  "domain", "supergroup", "division", "subdivision",
  "class", "order", "family", "genus", "species"
)

#' Parse one semicolon-delimited taxonomy string into named rank values
#'
#' Supports three formats:
#' \itemize{
#'   \item Prefix-style: \code{k__Kingdom;p__Phylum;...} (QIIME2 / RESCRIPt /
#'     SILVA). Also accepts \code{d__} (domain) as an alias for kingdom.
#'   \item Positional, 7 levels: \code{Kingdom;Phylum;Class;Order;Family;Genus;Species}
#'     (MIDORI2, plain SILVA). Levels are matched left-to-right against
#'     \code{.crabs_std_hierarchy}.
#'   \item Positional, 9 levels: PR2's fixed
#'     \code{Domain;Supergroup;Division;Subdivision;Class;Order;Family;Genus;Species}
#'     shape (see \code{.pr2_hierarchy}) -- disambiguated from the 7-level
#'     case purely by field count, confirmed uniform across a real PR2
#'     release.
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
  non_na <- parts[!is.na(parts)]
  has_prefix <- length(non_na) > 0L && any(grepl("^[a-z]__", non_na))

  if (has_prefix) {
    # Map single-letter prefix to canonical rank name
    prefix_map <- c(
      k = "kingdom", d = "kingdom", p = "phylum", c = "class",
      o = "order", f = "family", g = "genus", s = "species"
    )
    for (p in non_na) {
      m <- regmatches(p, regexpr("^([a-z])__(.+)$", p, perl = TRUE))
      if (length(m) == 0L || !nzchar(m)) next
      prefix <- substr(p, 1L, 1L)
      val <- sub("^[a-z]__", "", p)
      if (!nzchar(val)) next
      rank <- prefix_map[prefix]
      if (!is.na(rank) && rank %in% rank_system) {
        result[[rank]] <- val
      }
    }
  } else {
    # Positional mapping. PR2's fixed 9-level shape is distinguished from the
    # standard 7-level (MIDORI2/plain-SILVA) shape purely by field count --
    # confirmed uniform (always exactly 9, no missing levels) across a real
    # PR2 release; see .pr2_hierarchy's roxygen for the verification note.
    hierarchy <- if (length(parts) == length(.pr2_hierarchy)) {
      .pr2_hierarchy
    } else {
      .crabs_std_hierarchy
    }
    for (k in seq_along(parts)) {
      if (k > length(hierarchy)) break
      rank <- hierarchy[k]
      if (rank %in% rank_system && !is.na(parts[k])) {
        result[[rank]] <- parts[k]
      }
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
      taxonomy_file,
      sep = "\t", header = FALSE,
      col.names = c("seq_id", "tax_string"),
      quote = "", comment.char = "",
      stringsAsFactors = FALSE, fill = TRUE
    ),
    error = function(e) {
      stop(sprintf(
        "Failed to read taxonomy file '%s': %s",
        basename(taxonomy_file), conditionMessage(e)
      ))
    }
  )

  if (nrow(raw) == 0L) {
    stop(sprintf("Taxonomy file is empty: %s", basename(taxonomy_file)))
  }

  # Skip header rows: first field starts with "Feature", "feature", or "seq_id"
  if (grepl("^[Ff]eature|^seq.?id|^#", raw[1L, 1L])) raw <- raw[-1L, , drop = FALSE]

  if (nrow(raw) == 0L) {
    stop(sprintf(
      "Taxonomy file contained only a header row: %s",
      basename(taxonomy_file)
    ))
  }

  # Strip version suffixes from IDs for consistent matching with FASTA headers
  raw$seq_id <- sub("\\.[0-9]+$", "", trimws(raw$seq_id))

  # Parse unique taxonomy strings (many rows share the same string -- parse once)
  unique_strings <- unique(raw$tax_string)
  parsed_map <- lapply(unique_strings, .parse_tax_string, rank_system = rank_system)
  names(parsed_map) <- unique_strings

  # Build result data frame
  result_list <- lapply(seq_len(nrow(raw)), function(i) {
    row <- parsed_map[[raw$tax_string[i]]]
    c(composite_id = raw$seq_id[i], row)
  })

  out <- do.call(rbind, lapply(result_list, function(x) {
    as.data.frame(as.list(x), stringsAsFactors = FALSE)
  }))
  row.names(out) <- NULL
  out
}


#' Read a local FASTA file into a reference data frame
#'
#' Reads a FASTA file and joins it to a user-supplied taxonomy table to produce
#' a `reference_df` suitable for [build_sequence_matrix()].
#'
#' This is the local-file alternative to [fetch_ncbi_reference_sequences()].
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
#'   [fetch_ncbi_reference_sequences()] for downloading from NCBI,
#'   [build_sequence_matrix()]
#'
#' @examples
#' \dontrun{
#' # Option A: data frame taxonomy (existing behaviour)
#' tax <- data.frame(
#'   composite_id = c("ACC001", "ACC002"),
#'   family = c("Fundulidae", "Atherinopsidae"),
#'   genus = c("Fundulus", "Atherinops"),
#'   species = c("Fundulus parvipinnis", "Atherinops affinis")
#' )
#' ref <- read_reference_fasta("my_references.fasta", tax,
#'   rank_system = c("family", "genus", "species")
#' )
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
  if (!is.character(fasta_path) || length(fasta_path) != 1L) {
    stop("fasta_path must be a single file path")
  }
  if (!file.exists(fasta_path)) {
    stop(sprintf("File not found: %s", fasta_path))
  }
  if (file.info(fasta_path)$size == 0L) {
    stop(sprintf("FASTA file is empty (0 bytes): %s", fasta_path))
  }
  if (!is.null(taxonomy) && !is.null(taxonomy_file)) {
    stop("Supply either 'taxonomy' or 'taxonomy_file', not both")
  }
  if (is.null(taxonomy) && is.null(taxonomy_file)) {
    stop("One of 'taxonomy' or 'taxonomy_file' must be supplied")
  }

  rank_cols <- tolower(rank_system)

  # --- Resolve taxonomy -------------------------------------------------------
  if (!is.null(taxonomy_file)) {
    # Parse taxonomy from a TSV file (QIIME2 / RESCRIPt / SILVA / MIDORI2)
    if (!is.character(taxonomy_file) || length(taxonomy_file) != 1L) {
      stop("taxonomy_file must be a single file path")
    }
    if (!file.exists(taxonomy_file)) {
      stop(sprintf("taxonomy_file not found: %s", taxonomy_file))
    }
    taxonomy <- .parse_taxonomy_tsv(taxonomy_file, rank_cols)
  }

  if (!is.data.frame(taxonomy)) {
    stop("taxonomy must be a data frame")
  }

  names(taxonomy) <- tolower(names(taxonomy))

  needed <- c("composite_id", rank_cols)
  missing_cols <- setdiff(needed, names(taxonomy))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "taxonomy is missing required columns: %s",
      paste(missing_cols, collapse = ", ")
    ))
  }

  # Read and parse FASTA
  fasta_text <- paste(readLines(fasta_path, warn = FALSE), collapse = "\n")
  fasta_df <- .parse_fasta_text(fasta_text)

  if (nrow(fasta_df) == 0L) {
    stop("No sequences found in FASTA file (no headers detected)")
  }

  # Check for headers-only (no actual sequence data)
  has_seq <- nchar(fasta_df$sequence) > 0L
  if (!any(has_seq)) {
    stop("FASTA file contains headers but no sequence data")
  }
  if (any(!has_seq)) {
    n_empty <- sum(!has_seq)
    message(sprintf("Warning: %d header(s) with no sequence data will be dropped", n_empty))
    fasta_df <- fasta_df[has_seq, , drop = FALSE]
  }

  message(sprintf("Parsed %d sequences from %s", nrow(fasta_df), fasta_path))

  # Also strip version suffix from taxonomy composite_id for matching
  taxonomy$composite_id <- sub("\\.[0-9]+$", "", taxonomy$composite_id)

  # Join
  keep_cols <- c("composite_id", rank_cols)
  lookup <- taxonomy[!duplicated(taxonomy$composite_id), keep_cols,
    drop = FALSE
  ]
  reference_df <- merge(fasta_df, lookup, by = "composite_id", all.x = FALSE)
  reference_df <- reference_df[!is.na(reference_df$sequence) &
    nchar(reference_df$sequence) > 0L, , drop = FALSE]

  n_unmatched <- nrow(fasta_df) - nrow(reference_df)
  if (n_unmatched > 0L) {
    message(sprintf(
      "%d sequence(s) had no taxonomy match and were dropped",
      n_unmatched
    ))
  }

  message(sprintf("reference_df: %d sequences", nrow(reference_df)))
  reference_df
}
