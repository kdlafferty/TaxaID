# Edge: consensus_df -> taxa
# Source: simple extraction from consensus table

taxa <- unique({{input_var}}[[{{taxon_col}}]])
taxa <- taxa[!is.na(taxa) & nzchar(taxa)]
message("Extracted ", length(taxa), " unique taxa from consensus table")
taxa
