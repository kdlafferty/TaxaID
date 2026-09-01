# ==============================================================================
# check_marker_mismatch() -- cheap GBSeq feature-table cross-check for a
# reference accession's own annotated gene/product against the marker an
# evaluation was scoped to.
#
# Implements Question 2, item 4 of ecosystem_docs/REENTRY_PROMPT_
# investigate_flagged_accession_prefilter_group_posthoc.md. Directly
# grounded in a real, already-confirmed lesson from this ecosystem
# (AY850362, GreatLakes 12S audit, 2026-08-06/07): a genuine 16S-vs-12S
# MARKER mislabel, not a species mislabel -- what actually distinguished
# it from a real species mislabel (e.g. MZ605481) was the record's own
# annotated gene/product feature-table qualifier, NOT its taxonomic rank of
# disagreement (an earlier hypothesis, tested and refuted the hard way --
# see the reentry prompt's own Question 2, item 3). A single cheap GBSeq
# XML fetch, no BLAST, no alignment -- much cheaper than
# investigate_flagged_accession()'s deep dive, and meant to route a flagged
# accession to a completely different, much simpler resolution path
# (correct the marker label, or exclude the accession from THIS marker's
# reference set) before ever reaching that deep dive.
# ==============================================================================

#' Common marker-name synonyms as they actually appear in real GenBank
#' `/gene` and `/product` feature-table qualifiers -- deliberately a small,
#' hand-curated lookup (matches this ecosystem's existing precedent for
#' small marker registries, e.g. `TaxaTools::barcode_primer_defaults`), not
#' an attempt at an exhaustive marker ontology. Each value is a regular
#' expression (matched case-insensitively).
#' @noRd
.MARKER_ANNOTATION_PATTERNS <- list(
  "12S"  = "12S|s-?rRNA|small subunit ribosomal RNA",
  "16S"  = "16S|l-?rRNA|large subunit ribosomal RNA",
  "18S"  = "18S(\\s+ribosomal)?\\s*rRNA|18S",
  "COI"  = "\\bCOI\\b|\\bCO1\\b|\\bCOX1\\b|cytochrome c oxidase subunit I\\b",
  "CO1"  = "\\bCOI\\b|\\bCO1\\b|\\bCOX1\\b|cytochrome c oxidase subunit I\\b",
  "COX1" = "\\bCOI\\b|\\bCO1\\b|\\bCOX1\\b|cytochrome c oxidase subunit I\\b",
  "CYTB" = "cyt\\s*b|cytochrome b",
  "MATK" = "matK|maturase K",
  "RBCL" = "rbcL|ribulose.*carboxylase",
  "TRNL" = "trnL",
  "ITS"  = "internal transcribed spacer|\\bITS\\b",
  "ITS2" = "internal transcribed spacer\\s*2|\\bITS ?2\\b"
)

#' Resolve a marker name to the regex used to search annotation text
#'
#' Normalizes both the requested marker and the lookup's own keys
#' (uppercased, non-alphanumeric characters stripped) before matching. An
#' exact normalized match is tried first; failing that, a normalized key
#' that appears as a SUBSTRING of the normalized marker also resolves --
#' so a compound caller string like `"MiFish-12S"` or `"COI-Leray"` (real
#' `barcode_term`-style values used elsewhere in this ecosystem, e.g.
#' `TaxaTools::resolve_barcode_lengths()`) still correctly resolves to the
#' `"12S"`/`"COI"` pattern. An unlisted marker falls back to a literal,
#' case-insensitive match on `marker` itself -- still does something
#' reasonable rather than erroring on a marker this internal lookup doesn't
#' yet know about.
#' @noRd
.resolve_marker_pattern <- function(marker) {
  norm <- toupper(gsub("[^A-Za-z0-9]", "", marker))
  key_names <- names(.MARKER_ANNOTATION_PATTERNS)
  keys_norm <- toupper(gsub("[^A-Za-z0-9]", "", key_names))

  idx <- match(norm, keys_norm)
  if (is.na(idx)) {
    hit <- which(vapply(keys_norm, function(k) grepl(k, norm, fixed = TRUE), logical(1L)))
    if (length(hit) > 0L) idx <- hit[1L]
  }
  if (!is.na(idx)) return(.MARKER_ANNOTATION_PATTERNS[[idx]])

  gsub("([][{}()+*^$|\\\\.?])", "\\\\\\1", marker)
}

#' Fetch gene/CDS/rRNA/misc_feature annotation for a set of accessions
#'
#' One combined `rentrez::entrez_fetch(rettype = "gb", retmode = "xml")`
#' call per batch, same endpoint/pattern `.resolve_locations_by_acc()`
#' (`R/blast_sequences.R`) and `.fetch_reference_accession_records()`
#' (`R/evaluate_reference_accessions.R`) already use for accession-keyed
#' NCBI lookups -- extended here to read the feature table's `/gene` and
#' `/product` qualifiers instead of the `source` feature's `lat_lon`/
#' `country`, or the whole-record sequence/organism/create-date.
#'
#' @param accessions Character vector, deduped internally.
#' @return data.frame(accession, feature_key, gene, product, feature_from,
#'   feature_to). One row per (accession, matched feature) pair for
#'   `gene`/`CDS`/`rRNA`/`misc_feature` features found; an accession with NO
#'   such feature at all still gets exactly one row, with
#'   `feature_key`/`gene`/`product`/`feature_from`/`feature_to` all `NA` (so
#'   a caller can distinguish "checked, no relevant annotation exists" from
#'   "not fetched at all"). `feature_from`/`feature_to` (added 2026-09-01,
#'   for `.extract_feature_table_fallback()` in
#'   `R/trim_query_to_amplicon.R` -- the feature-table-guided extraction
#'   fallback for a query too long to primer-trim) are the min/max of the
#'   feature's own `GBFeature_intervals/GBInterval` `from`/`to` coordinates
#'   (numeric, 1-based, inclusive, as GenBank reports them) -- `NA` when the
#'   feature has no interval data at all. `check_marker_mismatch()` itself
#'   never reads these two columns; they exist purely so that function's
#'   own fetch/matching internals can be reused, not duplicated, by the
#'   extraction fallback.
#' @noRd
.fetch_marker_annotation <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  empty <- data.frame(accession = character(0L), feature_key = character(0L),
                      gene = character(0L), product = character(0L),
                      feature_from = numeric(0L), feature_to = numeric(0L),
                      stringsAsFactors = FALSE)

  .check_pkg("rentrez")
  .check_pkg("xml2")

  if (!is.null(ncbi_api_key) && nzchar(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  accessions <- unique(accessions[!is.na(accessions) & nzchar(accessions)])
  if (length(accessions) == 0L) return(empty)

  batch_size <- 100L
  batches    <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  res        <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    if (verbose)
      message(sprintf("Fetching marker annotation: batch %d/%d (%d accessions)...",
                      i, length(batches), length(batch)))
    for (attempt in 1:3) {
      fetched <- tryCatch({
        xml_raw <- rentrez::entrez_fetch(
          db = "nuccore", id = batch, rettype = "gb", retmode = "xml"
        )
        xml_doc <- xml2::read_xml(xml_raw)
        seqs    <- xml2::xml_find_all(xml_doc, "//GBSeq")

        do.call(rbind, lapply(seqs, function(node) {
          acc   <- xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_primary-accession"))
          feats <- xml2::xml_find_all(
            node,
            paste0(
              ".//GBFeature[GBFeature_key='gene' or GBFeature_key='CDS' or ",
              "GBFeature_key='rRNA' or GBFeature_key='misc_feature']"
            )
          )
          if (length(feats) == 0L) {
            return(data.frame(accession = acc, feature_key = NA_character_,
                              gene = NA_character_, product = NA_character_,
                              feature_from = NA_real_, feature_to = NA_real_,
                              stringsAsFactors = FALSE))
          }
          do.call(rbind, lapply(feats, function(feat) {
            fkey   <- xml2::xml_text(xml2::xml_find_first(feat, "./GBFeature_key"))
            qnames <- xml2::xml_text(xml2::xml_find_all(
              feat, "./GBFeature_quals/GBQualifier/GBQualifier_name"
            ))
            qvals  <- xml2::xml_text(xml2::xml_find_all(
              feat, "./GBFeature_quals/GBQualifier/GBQualifier_value"
            ))
            gene_val    <- qvals[qnames == "gene"]
            product_val <- qvals[qnames == "product"]
            # GBFeature_intervals/GBInterval's own from/to -- min/max across
            # every interval covers a multi-interval feature (e.g. a
            # spliced CDS) by its full outer span; NA when the feature
            # carries no interval data at all (found, not assumed).
            iv_from <- suppressWarnings(as.numeric(xml2::xml_text(xml2::xml_find_all(
              feat, "./GBFeature_intervals/GBInterval/GBInterval_from"
            ))))
            iv_to <- suppressWarnings(as.numeric(xml2::xml_text(xml2::xml_find_all(
              feat, "./GBFeature_intervals/GBInterval/GBInterval_to"
            ))))
            iv_all <- c(iv_from, iv_to)
            data.frame(
              accession   = acc,
              feature_key = fkey,
              gene        = if (length(gene_val) > 0L) gene_val[1L] else NA_character_,
              product     = if (length(product_val) > 0L) product_val[1L] else NA_character_,
              feature_from = if (any(!is.na(iv_all))) min(iv_all, na.rm = TRUE) else NA_real_,
              feature_to   = if (any(!is.na(iv_all))) max(iv_all, na.rm = TRUE) else NA_real_,
              stringsAsFactors = FALSE
            )
          }))
        }))
      }, error = function(e) {
        if (attempt < 3L) {
          Sys.sleep(attempt * 2)
          NULL
        } else {
          if (verbose) warning(sprintf(
            "Marker-annotation fetch failed for batch %d: %s", i, conditionMessage(e)
          ), call. = FALSE)
          empty  # already carries feature_from/feature_to (0-row, schema-only)
        }
      })
      if (!is.null(fetched)) { res[[i]] <- fetched; break }
    }
    if (i < length(batches)) Sys.sleep(0.4)
  }

  out <- do.call(rbind, Filter(Negate(is.null), res))
  if (is.null(out) || nrow(out) == 0L) return(empty)
  out
}

#' Cross-Check a Reference Accession's Own Annotated Gene/Product Against an Expected Marker
#'
#' Before investigating a flagged accession as a possible SPECIES mislabel
#' (see [investigate_flagged_accession()]), this does a single cheap GBSeq
#' XML fetch and checks the record's own `/gene` or `/product`
#' feature-table qualifier against the marker an evaluation was scoped to
#' (e.g. does a "12S"-scoped audit's flagged record actually say
#' `/product="16S ribosomal RNA"`?). No BLAST, no alignment -- much cheaper
#' than [investigate_flagged_accession()]'s deep dive, and meant to route a
#' flagged accession to a completely different, simpler resolution path
#' (correct the marker label, or exclude the accession from this marker's
#' own reference set) before ever reaching it.
#'
#' @section Why this exists (2026-08-08):
#' Directly grounded in a real, already-confirmed case from this ecosystem:
#' `AY850362` (a real GreatLakes 12S reference-database audit accession,
#' confirmed 2026-08-06/07) is a genuine 16S-vs-12S MARKER mislabel, not a
#' species mislabel. An earlier hypothesis -- that a disagreement resolved
#' only at a coarse taxonomic rank (family/order/phylum) signals a
#' marker/gene mislabel, while a disagreement at genus/species signals a
#' real species mislabel -- was tested directly against `MZ605481` (a real
#' confirmed SPECIES mislabel) and refuted: `MZ605481`'s own disagreement is
#' *also* recorded at a coarse rank (order), yet is a real species mislabel,
#' not a marker mislabel. What actually distinguishes the two is each
#' record's own annotated gene/product metadata, not its taxonomic rank of
#' disagreement -- this function checks that directly instead.
#'
#' @param accessions Character vector of accessions to check.
#' @param expected_marker Character scalar (e.g. `"12S"`, `"16S"`, `"COI"`)
#'   -- the marker/barcode the evaluation this accession was flagged under
#'   was scoped to. Matched case-insensitively against a small internal
#'   lookup of common marker-name synonyms as they actually appear in real
#'   GenBank `/gene`/`/product` qualifiers (e.g. `"12S"` also matches
#'   `"s-rRNA"`/`"small subunit ribosomal RNA"`); an unlisted marker falls
#'   back to a literal, case-insensitive substring match on
#'   `expected_marker` itself.
#' @param ncbi_api_key,verbose As in [evaluate_reference_accessions()].
#'
#' @return A data frame, one row per unique input accession:
#'   \describe{
#'     \item{`accession`}{As supplied.}
#'     \item{`expected_marker`}{As supplied.}
#'     \item{`annotated_genes`}{Semicolon-joined, deduplicated `/gene`
#'       qualifier values found anywhere in the record's feature table.
#'       `NA` if none were found (may still have `/product` annotation).}
#'     \item{`annotated_products`}{Same, for `/product`.}
#'     \item{`marker_match`}{`TRUE` if ANY annotated `/gene` or `/product`
#'       text matches `expected_marker`'s resolved pattern; `FALSE` if the
#'       record has real gene/CDS/rRNA/misc_feature annotation but none of
#'       it matches; `NA` if the record has NO such annotation to judge at
#'       all -- a distinct, honest outcome, not evidence of mismatch.}
#'   }
#'
#' @seealso [investigate_flagged_accession()], [evaluate_reference_accessions()]
#'
#' @export
check_marker_mismatch <- function(accessions, expected_marker,
                                  ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""),
                                  verbose = TRUE) {

  if (!is.character(accessions) || length(accessions) == 0L)
    stop("accessions must be a non-empty character vector.", call. = FALSE)
  if (!is.character(expected_marker) || length(expected_marker) != 1L ||
      is.na(expected_marker) || !nzchar(expected_marker))
    stop("expected_marker must be a single non-NA, non-blank character string.", call. = FALSE)

  unique_acc <- unique(accessions[!is.na(accessions) & nzchar(accessions)])
  if (length(unique_acc) == 0L)
    stop("No valid (non-NA, non-blank) accessions supplied.", call. = FALSE)

  pattern <- .resolve_marker_pattern(expected_marker)
  ann <- .fetch_marker_annotation(unique_acc, ncbi_api_key = ncbi_api_key, verbose = verbose)

  rows <- lapply(unique_acc, function(acc) {
    sub_ann <- ann[ann$accession == acc, , drop = FALSE]
    genes    <- unique(stats::na.omit(sub_ann$gene))
    products <- unique(stats::na.omit(sub_ann$product))
    has_annotation <- nrow(sub_ann) > 0L && any(!is.na(sub_ann$feature_key))
    match_any <- has_annotation && (
      any(grepl(pattern, genes, ignore.case = TRUE)) ||
      any(grepl(pattern, products, ignore.case = TRUE))
    )
    data.frame(
      accession = acc,
      expected_marker = expected_marker,
      annotated_genes = if (length(genes) > 0L) paste(genes, collapse = "; ") else NA_character_,
      annotated_products = if (length(products) > 0L) paste(products, collapse = "; ") else NA_character_,
      marker_match = if (!has_annotation) NA else match_any,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
