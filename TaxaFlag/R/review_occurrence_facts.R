# ==============================================================================
# TaxaFlag -- Occurrence facts for the LLM review prompt (guardrail G7)
# ==============================================================================
# The review is a judgement from the model's own knowledge, and the measured
# failures were concentrated where that knowledge is thinnest: taxa with few
# records, and sites at the edge of a range. Both are answerable from the run's
# own occurrence pool, which the pipeline has already fetched. Putting those
# facts in the prompt raised agreement with the maintainer's labels from 75% to
# 78% and precision from 80% to 84%, and the rows it newly acted on were 94%
# rows he also acted on.
#
# What goes in the prompt is a SUMMARY, never the records: counts, a latitude
# extent, and per detected site the distance to the nearest record and how many
# record locations lie within 50 km. Those are the same counts the geography
# override already uses, so the model and the override are reading the same
# evidence rather than two different summaries of it.

#' Great-circle distance in km from one point to many
#'
#' R = 6371 km, the value the rest of the ecosystem's distance code uses, so a
#' "nearest record" in the prompt is the same number the override computes.
#' @noRd
.haversine_km <- function(lat1, lon1, lat2, lon2) {
  r <- pi / 180
  a <- sin((lat2 - lat1) * r / 2)^2 +
    cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2
  2 * 6371 * asin(pmin(1, sqrt(a)))
}

#' Validate the occurrence pool and reduce it to what the facts need
#'
#' The column contract is the ecosystem's own: decimalLatitude/decimalLongitude
#' as TaxaFetch writes them, and the rank columns it carries. A missing required
#' column is an error, not an empty bracket -- an empty bracket reads as "no
#' records", and "we could not look" must never be served as "nothing there".
#'
#' point_id is optional. TaxaFetch::stack_occurrences() builds it by pasting
#' latitude and longitude, so when it is absent exactly that is derived here
#' rather than refusing the call.
#' @noRd
.validate_occurrence_data <- function(occurrence_data) {
  if (!is.data.frame(occurrence_data)) {
    stop("'occurrence_data' must be a data frame, or NULL.", call. = FALSE)
  }
  miss <- setdiff(c("decimalLatitude", "decimalLongitude"), names(occurrence_data))
  if (length(miss) > 0L) {
    stop(sprintf(
      paste0(
        "'occurrence_data' is missing column(s): %s. It must be an occurrence ",
        "table as TaxaFetch writes one (decimalLatitude, decimalLongitude, ",
        "point_id, and the rank columns to match on)."
      ),
      paste(miss, collapse = ", ")
    ), call. = FALSE)
  }
  lat <- suppressWarnings(as.numeric(occurrence_data$decimalLatitude))
  lon <- suppressWarnings(as.numeric(occurrence_data$decimalLongitude))
  # A record with no usable coordinate can neither be near a site nor widen a
  # latitude extent, so it is dropped before anything is counted. Counting it
  # would inflate n_records against a location count it cannot contribute to.
  keep <- !is.na(lat) & !is.na(lon) & abs(lat) <= 90 & abs(lon) <= 180
  out <- occurrence_data[keep, , drop = FALSE]
  if (nrow(out) == 0L) {
    stop(
      "'occurrence_data' has no records with usable coordinates.",
      call. = FALSE
    )
  }
  out$decimalLatitude <- lat[keep]
  out$decimalLongitude <- lon[keep]
  if (!"point_id" %in% names(out)) {
    out$point_id <- paste(out$decimalLatitude, out$decimalLongitude, sep = "_")
  } else {
    out$point_id <- as.character(out$point_id)
  }
  rownames(out) <- NULL
  out
}

#' The occurrence guideline, with the pool's own latitude extent
#'
#' The extent is computed, never assumed: a pool that stops at its own southern
#' edge would otherwise read as a range limit, which is exactly the error the
#' guardrails exist to prevent.
#' @noRd
.occurrence_guideline_text <- function(occurrence_data) {
  rng <- range(occurrence_data$decimalLatitude)
  paste0(
    '- An "[occurrence data: ...]" bracket gives occurrence records of this ',
    "taxon from the study's regional pool (all habitats; the pool covers only ",
    sprintf("%.1f-%.1f N", rng[1L], rng[2L]), ", so a latitude extent at ",
    "those edges is truncated by the pool, not a range limit). Use them: ",
    "several record locations near a site are strong evidence the taxon ",
    "occurs there. No records in the pool is weak evidence of absence: the ",
    "pool is incomplete, especially for rare, small or cryptic taxa and in ",
    "poorly sampled regions.\n"
  )
}

#' Which pool column a call of this rank should be matched on
#'
#' A name is not a key and a rank is not interchangeable with another: a genus
#' name looked up in a species column matches nothing, and a species name
#' looked up in a genus column matches the whole genus. So the column is chosen
#' by the call's own rank, and a rank the pool has no column for returns NULL --
#' which the bracket then reports as "not available", never as "no records".
#' @noRd
.occurrence_rank_col <- function(rank, occurrence_data) {
  if (is.null(rank) || length(rank) != 1L || is.na(rank)) {
    return(NULL)
  }
  rk <- tolower(trimws(rank))
  want <- switch(rk,
    species = "taxon_name",
    genus = "genus",
    family = "family",
    order = "order",
    class = "class",
    phylum = "phylum",
    NULL
  )
  if (is.null(want)) {
    return(NULL)
  }
  hit <- names(occurrence_data)[tolower(names(occurrence_data)) == want]
  if (length(hit) == 0L) NULL else hit[[1L]]
}

#' The "[detected at: ...]" bracket for one taxon
#'
#' Sites north to south, latitude to one decimal. A detected site the site
#' table does not know has no latitude, so it is left out here and takes the
#' study-wide verdict downstream; .validate_review_sites() has already warned
#' about it by name.
#' @noRd
.detected_sites_bracket <- function(site_vec, sites) {
  if (length(site_vec) == 0L) {
    return(NA_character_)
  }
  idx <- match(site_vec, sites$site)
  idx <- idx[!is.na(idx)]
  if (length(idx) == 0L) {
    return(NA_character_)
  }
  idx <- idx[order(-sites$lat[idx])]
  sprintf(
    "[detected at: %s]",
    paste(sprintf("%s (%.1f N)", sites$site[idx], sites$lat[idx]), collapse = "; ")
  )
}

#' The "[occurrence data: ...]" bracket for one taxon
#' @noRd
.occurrence_bracket <- function(taxon, rank, site_vec, occurrence_data, sites) {
  col <- .occurrence_rank_col(rank, occurrence_data)
  if (is.null(col)) {
    return("[occurrence data: rank not available in the pool]")
  }
  hit <- which(trimws(as.character(occurrence_data[[col]])) == trimws(taxon))
  if (length(hit) == 0L) {
    return("[occurrence data: no records of this taxon in the regional pool]")
  }
  o <- occurrence_data[hit, , drop = FALSE]
  idx <- match(site_vec, sites$site)
  idx <- idx[!is.na(idx)]
  idx <- idx[order(-sites$lat[idx])]
  per <- if (length(idx) == 0L) {
    character(0)
  } else {
    vapply(idx, function(k) {
      d <- .haversine_km(
        sites$lat[k], sites$lon[k], o$decimalLatitude, o$decimalLongitude
      )
      n50 <- length(unique(o$point_id[d <= 50]))
      sprintf(
        "%s: nearest record %.0f km, %d record location%s within 50 km",
        sites$site[k], min(d), n50, if (n50 == 1L) "" else "s"
      )
    }, character(1L))
  }
  sprintf(
    "[occurrence data: %s records at %s locations in the pool, latitude %.1f-%.1f N%s]",
    format(nrow(o), big.mark = ","),
    format(length(unique(o$point_id)), big.mark = ","),
    min(o$decimalLatitude), max(o$decimalLatitude),
    if (length(per) == 0L) "" else paste0("; ", paste(per, collapse = "; "))
  )
}

#' The sites where each reviewed label was detected
#'
#' One reviewed label can stand for several canonical candidate sets, so the
#' sites are gathered over every join key the label covers rather than by name.
#' Returned in north-to-south order so the bracket and the facts agree.
#' @noRd
.review_detected_sites <- function(labels, input_df, site_col, sites,
                                   label_canon_map = NULL) {
  by_key <- split(
    as.character(input_df[[site_col]]), as.character(input_df$.join_key)
  )
  lapply(labels, function(lab) {
    keys <- if (is.null(label_canon_map)) lab else label_canon_map[[lab]]
    v <- unique(unlist(by_key[as.character(keys)], use.names = FALSE))
    v <- v[!is.na(v) & v %in% sites$site]
    v[order(-sites$lat[match(v, sites$site)])]
  })
}
