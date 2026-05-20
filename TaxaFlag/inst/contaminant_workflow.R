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
    event_id  = sub(".*Palmyra(\\d+)\\..*", "Palmyra\\1", event_id),
    taxon_name = coalesce(Species, Genus, Family, Order, Class)
  )

# --- 3. Flag lab contaminants (extraction blanks) ----------------------------

lab_flags <- flag_contaminant(
  reads_long,
  taxon_col        = "taxon_name",
  control_samples  = c("Palmyra30", "Palmyra62"),
  exclude_samples  = c("Palmyra31", "Palmyra63",                # PCR blanks
                        "Palmyra32", "Palmyra64", "Palmyra70"),  # positive controls
  contaminant_type = "lab_contaminant"
)

lab_flags |> filter(flag_lab_contaminant != "likely")

# --- 4. Flag PCR contaminants (PCR blanks) -----------------------------------

pcr_flags <- flag_contaminant(
  reads_long,
  taxon_col        = "taxon_name",
  control_samples  = c("Palmyra31", "Palmyra63"),
  exclude_samples  = c("Palmyra30", "Palmyra62",                # extraction blanks
                        "Palmyra32", "Palmyra64", "Palmyra70"),  # positive controls
  contaminant_type = "lab_contaminant"
)

pcr_flags |> filter(flag_lab_contaminant != "likely")

# --- 5. Flag positive control leakage ---------------------------------------

pos_flags <- flag_contaminant(
  reads_long,
  taxon_col        = "taxon_name",
  control_samples  = c("Palmyra32", "Palmyra64", "Palmyra70"),
  exclude_samples  = c("Palmyra30", "Palmyra62",   # extraction blanks
                        "Palmyra31", "Palmyra63"),   # PCR blanks
  contaminant_type = "positive_control"
)

pos_flags |> filter(flag_positive_control != "likely")

# --- 6. Combine results -----------------------------------------------------
# Join all flag sets by taxon_name for a complete picture

all_flags <- lab_flags |>
  select(taxon_name, flag_lab_contaminant, flag_lab_contaminant_score) |>
  full_join(
    pcr_flags |> select(taxon_name, flag_pcr = flag_lab_contaminant,
                        flag_pcr_score = flag_lab_contaminant_score),
    by = "taxon_name"
  ) |>
  full_join(
    pos_flags |> select(taxon_name, flag_positive_control,
                        flag_positive_control_score),
    by = "taxon_name"
  ) |>
  arrange(pmin(flag_lab_contaminant_score, flag_pcr_score,
               flag_positive_control_score, na.rm = TRUE))

all_flags
