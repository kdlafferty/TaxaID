# load_all.R
# devtools::load_all() every TaxaID package from source, in dependency order.
# Faster than install_all.R for iterating on code — no reinstall, no restart —
# but only touches the current R session (nothing is written to the library).
# Run from any R session:
#   source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/load_all.R")
#
# Dependency order:
#   TaxaTools (foundation — no TaxaID dependencies)
#   TaxaFetch, TaxaMatch, TaxaHabitat, TaxaLikely  (depend on TaxaTools)
#   TaxaExpect                          (depends on TaxaTools, TaxaFetch, TaxaHabitat)
#   TaxaAssign                          (depends on TaxaTools, TaxaLikely, TaxaExpect)
#   TaxaFlag                            (depends on TaxaTools, TaxaAssign)
#   TaxaWizard                          (no TaxaID dependencies)

ROOT <- "~/My Drive/Rscripts/projects/TaxaID"

.load <- function(pkg) {
  path <- file.path(ROOT, pkg)
  message(sprintf("\n=== Loading %s ===", pkg))
  devtools::load_all(path, quiet = FALSE)
}

# ---- Tier 1: foundation ------------------------------------------------------
.load("TaxaTools")

# ---- Tier 2: depend on TaxaTools only ----------------------------------------
.load("TaxaFetch")
.load("TaxaMatch")
.load("TaxaHabitat")
.load("TaxaLikely")

# ---- Tier 3: depend on Tier 2 ------------------------------------------------
.load("TaxaExpect")

# ---- Tier 4: depend on Tier 3 ------------------------------------------------
.load("TaxaAssign")

# ---- Tier 5: depend on Tier 4 ------------------------------------------------
.load("TaxaFlag")

# ---- Standalone --------------------------------------------------------------
.load("TaxaWizard")

message("\n=== All TaxaID packages load_all()'d from source. ===")
