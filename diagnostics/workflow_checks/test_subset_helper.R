# Extract the subset block from the template and exercise it standalone.
tpl <- readLines("/Users/lafferty/My Drive/Rscripts/eDNA/PtConception/TaxaID_eDNA_Workflow_Template.R")
i <- grep("^SUBSET             <- FALSE", tpl); j <- grep("^# --- Workflow timing", tpl)
block <- tpl[i:(j-1)]
OUT_DIR <- tempdir(); OUT_PREFIX <- "TEST_sub"; SENTINEL_TAXA <- c("Girella nigricans")
eval(parse(text = paste(block, collapse="\n")))

# synthetic match object: long-tailed candidate counts, generic column names
set.seed(1)
mk <- function() {
  obs <- paste0("OBS_", sprintf("%04d", 1:800))
  n   <- c(rep(1L, 600), rep(3L, 150), sample(10:60, 50, TRUE))  # long tail
  do.call(rbind, Map(function(o, k) data.frame(
    observation_id = o, taxon_name = paste0("Sp_", seq_len(k)), stringsAsFactors = FALSE), obs, n))
}
x <- mk()
x$taxon_name[x$observation_id == "OBS_0777"] <- "Girella nigricans"   # sentinel
cat("full:", length(unique(x$observation_id)), "observations,", nrow(x), "rows\n")

cat("\n-- SUBSET = FALSE must be an exact no-op --\n")
SUBSET <- FALSE
stopifnot(identical(.subset_obs(x), x)); cat("   PASS\n")

cat("\n-- SUBSET = TRUE --\n")
SUBSET <- TRUE; SUBSET_N <- 100L; SUBSET_WIDE_N <- 20L
SUBSET_SEED <- 20260917L; SUBSET_ALWAYS_TAXA <- SENTINEL_TAXA; REUSE_PREFIX <- NULL
a <- .subset_obs(x)
cat("   kept:", length(unique(a$observation_id)), "observations\n")
stopifnot("OBS_0777" %in% a$observation_id); cat("   PASS sentinel guaranteed\n")
wide_full <- names(sort(table(x$observation_id), decreasing=TRUE))[1:20]
stopifnot(all(wide_full %in% a$observation_id)); cat("   PASS widest 20 present\n")

cat("\n-- reproducible across calls --\n")
b <- .subset_obs(x)
stopifnot(identical(sort(unique(a$observation_id)), sort(unique(b$observation_id)))); cat("   PASS\n")

cat("\n-- does it hijack the global RNG stream? --\n")
set.seed(42); before <- runif(3)
set.seed(42); invisible(.subset_obs(x)); after <- runif(3)
if (isTRUE(all.equal(before, after))) cat("   PASS RNG stream preserved\n") else {
  cat("   FAIL: RNG stream CHANGED\n     before:", before, "\n     after: ", after, "\n")
}

cat("\n-- stamping --\n")
.save(a, "probe")
st <- attr(readRDS(file.path(OUT_DIR, "TEST_sub_probe.rds")), "taxaid_subset")
stopifnot(isTRUE(st$subset), st$seed == 20260917L); cat("   PASS stamp on checkpoint\n")
SUBSET <- FALSE; .save(a, "probe2")
stopifnot(is.null(attr(readRDS(file.path(OUT_DIR,"TEST_sub_probe2.rds")), "taxaid_subset")))
cat("   PASS no stamp on a full run\n")

cat("\n-- list-shaped pipeline objects (evaluate_likelihoods() output) --\n")
# REGRESSION: lik_result is list(likelihoods=, unresolved=), not a data frame.
# The first version asserted obs_col %in% names(x) and died on the real
# PtConception checkpoint at the one line that matters. Both frames must be cut
# to the SAME observation set, or they diverge.
SUBSET <- TRUE
lst <- list(likelihoods = x,
            unresolved  = x[x$observation_id %in% head(unique(x$observation_id), 40), ],
            model_note  = "not a data frame -- must pass through untouched")
out <- .subset_obs(lst)
stopifnot(identical(names(out), names(lst)))
stopifnot(is.character(out$model_note))
k1 <- unique(out$likelihoods$observation_id); k2 <- unique(out$unresolved$observation_id)
stopifnot(all(k2 %in% k1))                       # consistent, never divergent
stopifnot(length(k1) < length(unique(x$observation_id)))
cat(sprintf("   PASS both frames cut to one set (%d obs; unresolved %d -> %d rows)\n",
            length(k1), nrow(lst$unresolved), nrow(out$unresolved)))

cat("\n-- a zero-row frame in the list must not error --\n")
lst0 <- list(likelihoods = x, unresolved = x[0, ])
out0 <- .subset_obs(lst0)
stopifnot(nrow(out0$unresolved) == 0L); cat("   PASS\n")

cat("\n-- a list with no observation_id anywhere must fail LOUDLY --\n")
bad <- tryCatch({ .subset_obs(list(a = data.frame(z = 1))); FALSE },
                error = function(e) TRUE)
stopifnot(bad); cat("   PASS errors rather than silently returning everything\n")

cat("\nAll checks passed.\n")
