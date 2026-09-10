# =============================================================================
# TaxaFlag — Contaminant Detection Workflow
# =============================================================================
# Input: wide-format read table (e.g., DADA2/eDNA output) with sample columns
# Output: per-taxon contaminant flags for lab, field, and positive control checks
#
# Example data: Palmyra2017_MiFishU_tab+taxa.csv
# Blanks: Palmyra30/62 (extraction), Palmyra31/63 (PCR)
# Positive controls: Palmyra32/64/70

library(tidyr)
library(dplyr)
library(TaxaFlag)

# --- 1. Load data -----------------------------------------------------------

# raw <- read.csv(file.choose())   # interactive
raw <- read.csv("/Users/lafferty/My Drive/Stats and Data/Palmyra eDNA/2017eDNA/Palmyra2017_MiFishU_tab+taxa.csv")

# --- 2. Pivot to long format ------------------------------------------------
# flag_contaminant() requires long format: one row per sample x taxon

reads_long <- raw |>
  pivot_longer(
    cols = starts_with("Lafferty01_"),
    names_to = "event_id",
    values_to = "n_reads"
  ) |>
  mutate(
    event_id = sub(".*Palmyra(\\d+)\\..*", "Palmyra\\1", event_id),
    taxon_name = coalesce(Species, Genus, Family, Order, Class)
  )

# --- 3. Flag lab contaminants (extraction blanks) ----------------------------

lab_flags <- flag_contaminant(
  reads_long,
  taxon_col = "taxon_name",
  control_samples = c("Palmyra30", "Palmyra62"),
  exclude_samples = c(
    "Palmyra31", "Palmyra63", # PCR blanks
    "Palmyra32", "Palmyra64", "Palmyra70"
  ), # positive controls
  contaminant_type = "lab_contaminant"
)

lab_flags |> filter(validity_flag != "valid")

# --- 4. Flag PCR contaminants (PCR blanks) -----------------------------------

pcr_flags <- flag_contaminant(
  reads_long,
  taxon_col = "taxon_name",
  control_samples = c("Palmyra31", "Palmyra63"),
  exclude_samples = c(
    "Palmyra30", "Palmyra62", # extraction blanks
    "Palmyra32", "Palmyra64", "Palmyra70"
  ), # positive controls
  contaminant_type = "lab_contaminant"
)

pcr_flags |> filter(validity_flag != "valid")

# --- 5. Flag positive control leakage ---------------------------------------
# This pattern (running the positive control itself as a "control sample" so
# any field reads of the spiked species are flagged as leakage) is correct
# ONLY for a NON-NATIVE spike -- a species that cannot genuinely occur in
# your field samples, so any field detection must be cross-talk. For a
# NATIVE spike (a real species of interest that might legitimately be
# present), do NOT run it through flag_contaminant() this way: it would
# flag and delete genuine field detections, since a spike is by
# construction the dominant taxon in its own control. A native spike should
# instead only ever appear in `exclude_samples` (as the other two calls
# above already do for Palmyra32/64/70), with recovery confirmed separately
# by checking its own read count in the control. See
# ecosystem_docs/POSITIVE_CONTROLS_design_options.md (2026-09-07) for the
# full native/non-native design discussion and the recommended paired-spike
# (non-native + native together) pattern for measuring per-sample leakage.

pos_flags <- flag_contaminant(
  reads_long,
  taxon_col = "taxon_name",
  control_samples = c("Palmyra32", "Palmyra64", "Palmyra70"),
  exclude_samples = c(
    "Palmyra30", "Palmyra62", # extraction blanks
    "Palmyra31", "Palmyra63"
  ), # PCR blanks
  contaminant_type = "positive_control"
)

pos_flags |> filter(validity_flag != "valid")

# --- 6. Combine results -----------------------------------------------------
# Join all flag sets by taxon_name for a complete picture. Each call shares
# the unified observation_validity/validity_flag/validity_reason schema
# (contaminant_type only changes the qualifier embedded in validity_flag's
# value, e.g. "invalid_lab_contaminant" -- not the column names), so each
# set's columns are renamed with a per-check prefix before joining.

all_flags <- lab_flags |>
  select(taxon_name,
    lab_validity       = observation_validity,
    lab_validity_flag  = validity_flag
  ) |>
  full_join(
    pcr_flags |> select(taxon_name,
      pcr_validity      = observation_validity,
      pcr_validity_flag = validity_flag
    ),
    by = "taxon_name"
  ) |>
  full_join(
    pos_flags |> select(taxon_name,
      pos_validity      = observation_validity,
      pos_validity_flag = validity_flag
    ),
    by = "taxon_name"
  ) |>
  arrange(pmin(lab_validity, pcr_validity, pos_validity, na.rm = TRUE))

all_flags
