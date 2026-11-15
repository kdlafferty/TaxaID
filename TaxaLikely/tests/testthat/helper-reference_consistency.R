# Fixtures for test-reference_consistency.R: a small library shaped like build_sequence_matrix() output
# (one row per unordered pair; coverage 1), built on the CI 12S AF488489 case.
#   - Pleuro verticalis has exactly two references: AF488489 (in truth a P. coenosus: 99.4% to five
#     independent P. coenosus references, 92.3% to its conspecific) and OQ846368 (correct: 97.1% to the
#     two P. decurrens references, 92.3% to AF488489).
#   - MT999001 is labelled Sebastes miniatus (family Sebastidae, the only one) but is 99.6% to the
#     P. coenosus references: the existing screen's family-rank "remove" case.
.rc_refs <- function(drop_coenosus_support = FALSE) {
  co <- c("KX100001", "MN200002", "OP300003", "PP400004", "LC500005")
  if (drop_coenosus_support) co <- co[1L]
  data.frame(
    id = c("AF488489", "OQ846368", co, "KY611111", "MZ722222", "MT999001", "JQ833333", "JX944444"),
    species = c("Pleuro verticalis", "Pleuro verticalis", rep("Pleuro coenosus", length(co)),
                "Pleuro decurrens", "Pleuro decurrens", "Sebastes miniatus", "Hippo stenolepis", "Hippo stenolepis"),
    stringsAsFactors = FALSE
  )
}
.rc_pid <- function(a, b) {
  s <- sort(c(a$species, b$species)); key <- paste(s, collapse = "|")
  ids <- sort(c(a$id, b$id))
  if (identical(ids, sort(c("AF488489", "OQ846368")))) return(0.923)
  if ("AF488489" %in% ids && "Pleuro coenosus" %in% s) return(0.994)
  if ("AF488489" %in% ids) return(0.90)
  if ("OQ846368" %in% ids && "Pleuro decurrens" %in% s) return(0.971)
  if ("OQ846368" %in% ids) return(0.92)
  if ("MT999001" %in% ids && "Pleuro coenosus" %in% s) return(0.996)
  if ("MT999001" %in% ids) return(0.85)
  switch(key,
    "Pleuro coenosus|Pleuro coenosus" = 0.997, "Pleuro decurrens|Pleuro decurrens" = 0.998,
    "Pleuro coenosus|Pleuro decurrens" = 0.95, "Hippo stenolepis|Hippo stenolepis" = 0.999,
    0.82
  )
}
.rc_raw_df <- function(...) {
  r <- .rc_refs(...)
  lin <- function(sp) {
    g <- sub(" .*", "", sp)
    data.frame(species = sp, genus = g,
               family = ifelse(g == "Sebastes", "Sebastidae", "Pleuronectidae"), stringsAsFactors = FALSE)
  }
  pr <- utils::combn(nrow(r), 2L)
  x <- r[pr[1L, ], ]; y <- r[pr[2L, ], ]
  lx <- lin(x$species); ly <- lin(y$species)
  data.frame(
    id_x = x$id, id_y = y$id,
    p_match = vapply(seq_len(ncol(pr)), function(k) .rc_pid(x[k, ], y[k, ]), numeric(1)),
    coverage = 1,
    species.x = lx$species, genus.x = lx$genus, family.x = lx$family,
    species.y = ly$species, genus.y = ly$genus, family.y = ly$family,
    stringsAsFactors = FALSE
  )
}
.rc_rs <- c("family", "genus", "species")
.rc_train <- function(df, ...) {
  set.seed(42L)
  suppressWarnings(suppressMessages(train_likelihood_model(df, .rc_rs, ...)))
}
