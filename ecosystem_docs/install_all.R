# install_all.R
# Install all TaxaID packages in dependency order.
# Run from any R session:
#   source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
#
# Dependency order:
#   TaxaTools (foundation — no TaxaID dependencies)
#   TaxaFetch, TaxaMatch, TaxaHabitat  (depend on TaxaTools)
#   TaxaLikely                          (depends on TaxaTools)
#   TaxaExpect                          (depends on TaxaTools, TaxaFetch, TaxaHabitat)
#   TaxaAssign                          (depends on TaxaTools, TaxaLikely, TaxaExpect)
#   TaxaFlag                            (depends on TaxaTools, TaxaAssign)
#   TaxaWizard                          (no TaxaID dependencies)

ROOT <- "~/My Drive/Rscripts/projects/TaxaID"

.install <- function(pkg) {
  path <- file.path(ROOT, pkg)
  message(sprintf("\n=== Installing %s ===", pkg))
  devtools::install(path, quiet = FALSE, upgrade = FALSE)
}

# ---- Tier 1: foundation ------------------------------------------------------
.install("TaxaTools")

# ---- Tier 2: depend on TaxaTools only ----------------------------------------
.install("TaxaFetch")
.install("TaxaMatch")
.install("TaxaHabitat")
.install("TaxaLikely")

# ---- Tier 3: depend on Tier 2 ------------------------------------------------
.install("TaxaExpect")

# ---- Tier 4: depend on Tier 3 ------------------------------------------------
.install("TaxaAssign")

# ---- Tier 5: depend on Tier 4 ------------------------------------------------
.install("TaxaFlag")

# ---- Standalone --------------------------------------------------------------
.install("TaxaWizard")

message("\n=== All TaxaID packages installed. Restart R before loading. ===")
