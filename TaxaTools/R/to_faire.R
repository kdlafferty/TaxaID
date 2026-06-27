# ==============================================================================
# to_faire.R
# TaxaTools -- Export TaxaID output as FAIRe-compatible taxaRaw/taxaFinal table
#
# FAIRe checklist: https://github.com/FAIR-eDNA/FAIRe_checklist
# Takahashi et al. (2025) Environmental DNA. doi:10.1002/edn3.70100
# ==============================================================================

#' Export a TaxaID Data Frame in FAIRe Checklist Format
#'
#' Converts a TaxaID output data frame (match object, likelihood object, or
#' posterior object) to the column naming conventions of the
#' [FAIRe eDNA metadata checklist](https://github.com/FAIR-eDNA/FAIRe_checklist)
#' (Takahashi et al. 2025), specifically the `taxaRaw` and `taxaFinal` classes.
#'
#' @param input_df A TaxaID data frame. Any output from `TaxaMatch`, `TaxaLikely`,
#'   or `TaxaAssign` is accepted. Columns not covered by the FAIRe field
#'   mapping are retained with their original names.
#' @param table_type Character. `"taxaFinal"` (post-curation assignments,
#'   e.g. posterior consensus output; default) or `"taxaRaw"` (pre-curation
#'   assignments, e.g. direct match output). Affects only the `faire_table`
#'   attribute attached to the returned data frame.
#' @param checkls_ver Character. FAIRe checklist version to record in the
#'   `checkls_ver` column. Default `"1.02"` (current stable version).
#' @param assay_name Character or `NULL`. Value to use for the FAIRe
#'   `assay_name` field when `df` does not contain a `testid` column. If
#'   `NULL` and `testid` is absent, `assay_name` is omitted from the output
#'   with a message.
#'
#' @return A data frame with FAIRe-compatible column names and a
#'   `faire_table` attribute recording `table_type` and `checkls_ver`.
#'
#' @details
#' **Column mapping applied (TaxaID \eqn{\to} FAIRe):**
#' \itemize{
#'   \item `observation_id` \eqn{\to} `seq_id`
#'   \item `taxon_name` \eqn{\to} `scientificName`
#'   \item `taxon_name_rank` \eqn{\to} `taxonRank`
#'   \item `score` \eqn{\to} `percent_match`
#'   \item `coverage` \eqn{\to} `percent_query_cover`
#'   \item `testid` \eqn{\to} `assay_name`
#'   \item `accession` \eqn{\to} `accession_id`
#'   \item `kingdom`, `phylum`, `class`, `order`, `family`, `genus`,
#'     `species` -- unchanged (already match FAIRe / Darwin Core names)
#' }
#'
#' **Columns constructed:**
#' \itemize{
#'   \item `verbatimIdentification` -- semicolon-delimited taxonomy string
#'     (FAIRe convention) built from whichever of kingdom through species are
#'     present and non-NA in each row.
#'   \item `specificEpithet` -- species epithet extracted from the `species`
#'     column (second word of the binomial), when `species` is present.
#'   \item `checkls_ver` -- FAIRe checklist version (Mandatory field).
#' }
#'
#' **Scope:** The FAIRe checklist covers the full eDNA workflow including
#' sample collection, extraction, PCR, and sequencing. TaxaID outputs map
#' only to the `taxaRaw` and `taxaFinal` classes (bioinformatics taxonomic
#' assignment tables). Sample-level metadata (`samp_name`, `eventDate`,
#' `decimalLatitude`, etc.) must be supplied by the user from field records
#' and joined to this output before submission.
#'
#' @references
#' Takahashi et al. (2025). FAIRe: A metadata checklist for FAIR
#' environmental DNA data. *Environmental DNA*.
#' \doi{10.1002/edn3.70100}
#'
#' @seealso [rename_cols()] for general-purpose column renaming.
#'
#' @export
#'
#' @examples
#' match_df <- data.frame(
#'   observation_id  = c("ASV1", "ASV2"),
#'   taxon_name      = c("Fundulus parvipinnis", "Atherinops affinis"),
#'   taxon_name_rank = c("species", "species"),
#'   score           = c(98.7, 95.1),
#'   coverage        = c(0.98, 0.94),
#'   accession       = c("MG002616.1", "KT215432.1"),
#'   family          = c("Fundulidae", "Atherinopsidae"),
#'   genus           = c("Fundulus", "Atherinops"),
#'   species         = c("Fundulus parvipinnis", "Atherinops affinis"),
#'   testid          = c("MiFishU", "MiFishU"),
#'   stringsAsFactors = FALSE
#' )
#'
#' faire_df <- to_faire(match_df, table_type = "taxaRaw")
#' names(faire_df)
to_faire <- function(input_df,
                     table_type  = c("taxaFinal", "taxaRaw"),
                     checkls_ver = "1.02",
                     assay_name  = NULL) {

  table_type <- match.arg(table_type)

  if (!is.data.frame(input_df)) {
    stop("`input_df` must be a data frame.", call. = FALSE)
  }
  if (!is.character(checkls_ver) || length(checkls_ver) != 1L ||
      !nzchar(checkls_ver)) {
    stop("`checkls_ver` must be a non-empty single string.", call. = FALSE)
  }
  if (!is.null(assay_name) &&
      (!is.character(assay_name) || length(assay_name) != 1L ||
       !nzchar(assay_name))) {
    stop("`assay_name` must be a non-empty single string or NULL.", call. = FALSE)
  }

  # ---------------------------------------------------------------------------
  # Column rename map: TaxaID -> FAIRe
  # ---------------------------------------------------------------------------
  rename_map <- c(
    observation_id  = "seq_id",
    taxon_name      = "scientificName",
    taxon_name_rank = "taxonRank",
    score           = "percent_match",
    coverage        = "percent_query_cover",
    accession       = "accession_id",
    testid          = "assay_name"
  )

  # Handle assay_name: testid absent but user supplied assay_name
  if (!"testid" %in% names(input_df)) {
    rename_map <- rename_map[names(rename_map) != "testid"]
    if (!is.null(assay_name)) {
      input_df[["assay_name"]] <- assay_name
    } else {
      message(
        "to_faire: `testid` column not found and `assay_name` not supplied; ",
        "`assay_name` column omitted from output."
      )
    }
  }

  # Apply renames for columns present in input_df
  for (taxaid_col in names(rename_map)) {
    if (taxaid_col %in% names(input_df)) {
      names(input_df)[names(input_df) == taxaid_col] <- rename_map[[taxaid_col]]
    }
  }

  # ---------------------------------------------------------------------------
  # Construct verbatimIdentification (semicolon-delimited lineage string)
  # ---------------------------------------------------------------------------
  tax_ranks     <- c("kingdom", "phylum", "class", "order",
                     "family", "genus", "species")
  present_ranks <- intersect(tax_ranks, names(input_df))

  if (length(present_ranks) > 0L) {
    input_df[["verbatimIdentification"]] <- apply(
      input_df[present_ranks], 1L,
      function(row) {
        vals <- row[!is.na(row) & nzchar(row)]
        if (length(vals) == 0L) NA_character_ else paste(vals, collapse = "; ")
      }
    )
  }

  # ---------------------------------------------------------------------------
  # Construct specificEpithet from species column (second word of binomial)
  # ---------------------------------------------------------------------------
  if ("species" %in% names(input_df)) {
    input_df[["specificEpithet"]] <- sub("^\\S+\\s+", "", input_df[["species"]])
    # Where species is NA or has no space (genus-only entry), return NA
    input_df[["specificEpithet"]][
      is.na(input_df[["species"]]) | !grepl(" ", input_df[["species"]], fixed = TRUE)
    ] <- NA_character_
  }

  # ---------------------------------------------------------------------------
  # Add mandatory checkls_ver field
  # ---------------------------------------------------------------------------
  input_df[["checkls_ver"]] <- checkls_ver

  # ---------------------------------------------------------------------------
  # Attach FAIRe metadata attribute
  # ---------------------------------------------------------------------------
  attr(input_df, "faire_table") <- list(
    table_type  = table_type,
    checkls_ver = checkls_ver
  )

  input_df
}
