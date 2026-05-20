#great_lakes fishes
library(TaxaLikely)
library(TaxaTools)
library(tidyverse)
#start by uploading a species list.
# ---- 1. Load inputs ----------------------------------------------------------
# We need genus + species columns from the reference.
# Can use reference_df, or extract from the match object.
# great_lakes_fish_species
# great_lakes_fish_species_expanded

ranks_to_use<-c("order","family", "genus", "species")
species_df <- read_csv(file.choose())# a csv with species binomials (should have a species column)
marker<-c("small subunit ribosomal RNA","18S")
#clean up list and put into GBIF backbone
clean_taxon_list<-species_df$species%>%
  clean_taxon_names(.)%>% #cleans out names
  verify_taxon_names(.,backbone_id = 11)%>% #establishes a backbone and ranks.
  change_backbone(input_col = "user_supplied_name")%>%#parse the hierarchy into columns.
  create_taxon_names(., rank_system = ranks_to_use)%>%
  dplyr::select(ranks_to_use)

#first step, what fraction of species have at least one reference sequence for the markers of interest?
coverage <- audit_barcode_coverage(
  match_df     = clean_taxon_list,
  barcode_term = marker,          # your marker: "COI", "ITS2", etc.
  target_rank  = "species",
  # max_date    = "2024/12/31",  # match GenBank state when reference was built
  # min_len     = NULL,          # auto-resolved from barcode_term
  # max_len     = NULL,
  # species_list = my_external_species_list,  # optional: FishBase, WoRMS, etc.
  ncbi_api_key = Sys.getenv("ENTREZ_KEY")
)
coverage$unreferenced # a list of species that lack a reference sequence (undetectable species)


##Next let's see if there are errors in the reference database that we want to exclude.
##Since we often get matches to the family level, we want to check them all, even species
##outside the geographic sampling area.
# ==============================================================================
# FETCH RELATIVES FROM NCBI
# ==============================================================================
# Use this when you need sequences beyond what's in your match object.
# The match object only contains sequences that matched your queries --
# a biased subset. A good model needs the broader picture: within-species
# variation, between-species distances, and related taxa.
#
# fetch_reference_sequences() searches NCBI by taxon name + barcode marker.
# It does a count-first estimation before committing to any download, so
# you can see how large the search is before proceeding.
# taxa: character vector of taxon names at any rank.
#   Can be genera, families, orders, or even a class.
#   Each is searched separately; results are combined.
taxa <- clean_taxon_list$family|>unique()
taxa<-"Cypriniformes"
# barcode_term: the marker(s) to search for.
#   Use a vector for synonyms: c("COI", "Co1", "Coxi", "Cox1")

# rank_system: coarse to fine, matching the taxonomy columns you want.
rank_system <- c("order","family", "genus", "species")

# ---- A2. Estimate search size (automatic) -----------------------------------
# fetch_reference_sequences() always runs a count-first pass.
# If the total exceeds max_sequences (default 10,000), it stops and
# shows you the per-taxon counts so you can adjust.
#
# For very large taxa (e.g., an entire class like "Actinopterygii"),
# you may need to:
#   - Break into smaller groups (families or genera)
#   - Add date filtering (min_date / max_date)
#   - Increase max_sequences if you're prepared to wait

# ---- A3. Fetch ---------------------------------------------------------------
reference_df <- fetch_reference_sequences(
  taxa         = taxa,
  barcode_term = marker,
  max_per_species = NULL,
  rank_system  = rank_system,

  # Optional controls:
  # min_len = 100,        # override auto-detected length filter
  # max_len = 600,        # (NULL = use barcode_term defaults)
  # max_per_species = 5,  # stratified downsampling (default 5)
  # max_per_genus = NULL,  # genus-level cap (NULL = no cap)
  max_sequences = 50000, # safety valve before downloading
  # blacklist_regex = "uncultured|environmental|predicted",
  # min_date = "2010/01/01",  # earliest publication date
  # max_date = "2024/12/31",  # latest publication date
  # cache_dir = "ncbi_cache",  # enable resumable downloads
  ncbi_api_key = Sys.getenv("ENTREZ_KEY")  # faster rate limit (user must establish this in their system)
)
reference_df$family%>%unique()
reference_df%>%filter(composite_id=="MZ005793")
##NEXT lets create a sequence matrix so we can compare within and among taxa.
rank_system <- c("family", "genus", "species")

ref_matrix <- build_reference_matrix(
  reference_df = reference_df,
  rank_system  = rank_system,
  max_dist = 1,    # pairs above 25% divergence are dropped (default)
  min_seq_len = 10,  # drop short sequences
  max_seq_len = 5000 # drop very long sequences
)

errors <- flag_reference_errors(
  raw_df            = ref_matrix,
  mislabel_threshold = 0.0,    # margin (in p_match units) required to count as an error
  return_all        = TRUE    # TRUE to also see "clean" sequences
)

errant_accessions<-errors%>%filter(error_type=="likely_mislabeled")#accessions that match other species better than their own species
suspicious_accessions<-errors%>%filter(error_type=="unverified_singleton_high_match")#accessions that closely match other species but have no within-species comparison

nrow(reference_df)
length(errant_accessions)
length(suspicious_accessions)
errant_accessions
errant_accessions%>%filter(species_x=="Pseudorasbora ")

## Now, errant or suspicious accessions can be removed (or flagged) before or after matching with sample sequences.
df1<-errors$species_x%>% #cleans out names
  verify_taxon_names(.,backbone_id = 4)%>% #establishes a backbone and ranks.
  change_backbone(input_col = "user_supplied_name")%>%#parse the hierarchy into columns.
  create_taxon_names(., rank_system = ranks_to_use)%>%
  dplyr::select(ranks_to_use)
df1%>%filter(id_x=="MZ005793")
df1$family%>%unique()
