#"Custom R functions for Species Lists"
#author: "Kevin Lafferty"
#date: "4/3/2024"

##if taxize fails to install, try:
##library(remotes)
##install_github("ropensci/taxize")
##
#BiocManager::install(version = "3.20")
#BiocManager::install("DECIPHER")

library(tidyverse)
library(taxize)
library(rentrez)
library(stringdist)

#This markdown file provides custom functions used in the paper Geographically Refined eDNA Taxonomic Assignment. 
#However, see the paper for detailed methods and rationale. The package was motivated by the desire to use geographic range information
# when determining consensus taxonomy for environment DNA studies. Doing so requires combining species lists from different sources. 
# The functions are divided into three main themes: species lists, geography, and consensus taxonomy. 

#Species Lists: Several challenges arise when dealing with species nomenclature. 
#Names change, people make spelling errors and abbreviation conventions are common, and different nomenclatures are used. 
#This becomes especially problematic when trying to combine information from different lists. 
#The R package Taxize is a great tool for dealing with species lists and is a required part of this package. 
#The functions build on taxize to facilitate working with and joining long lists.

#Imagine that one has two dataframes to join with at least one taxonomic name column. 
#Joining the dataframes  can lead to errors if the dataframes have different taxonomic sources, requiring some data cleaning. 
#The first step removes common abbreviations like spp. or sp. or sp. x. 
#Then, one finds the lowest common taxon (taxon_name) per row (e.g., some rows may be to species and others to family). 
#One then corrects potential spelling errors in the taxon_name. After correcting for spelling errors, a common taxonomic reference is chosen (e.g., NCBI), 
#from which a taxon ID is obtained. If a row cannot be matched to a taxon ID, research can determine whether a new name is required 
#or the row should be defined at a higher taxonomic rank. At this point, it is  possible to generate taxonomic ranks for each row and repeat the process
# of choosing a taxon_name, if desired. By keeping the original uncorrected name, the corrected species list can be rejoined with the original dataframe, 
# after which two dataframes can be joined. In most cases, no changes will occur. It is recommended that minor changes be documented and investigated 
# before accepting.

#Geography: The functions here do not determine species ranges. Rather it is of interest how species ranges relate to a defined region of interest. 
#For instance, some species are common at a location, whereas others have not been recorded. There are at least N ways to approach this problem. 
#We can start with a list of species with unknown distributions and seek to generate distribution information for them, 
#or we can start with a list of species known from the study system and see how they relate to a list of species with other data.
#
#
##FUNCTIONS LIBRARY
#COLLATE NAMES: 
#f_collate_names
# Requires a dataframe with taxonomy (df) that includes a "species" column (specis_col_name). 
# Strips the selected column of subspecies and strain designations. This can be helpful when dealing with 
# species lists from reports and papers. Such sources often have idiosyncratic ways of indicating uncertainty,
# like Genus sp. Or Genus sp1. These abbreviations often need to be cleaned up before a species list can be combined
# with other sources.
# 
f_collate_names <- function(df,collate_col,remove_abbr) {
  myenc <- enquo(collate_col)
  original<-df%>% 
    pull({{collate_col}}) %>%
    gsub(" ", " ", .) #gemini's suggested replacement
    #gsub("\xca", " ",.) # helps with non-breaking spaces accidentally introduced.  But caused Jessie to have errors on a PC.
  new<-original%>% 
    trimws() %>% #trim trailing or leading white spaces that form from pasting.
    #mutate({{collate_col}}:=gsub("[<ca>]"," ",{{collate_col}})) %>% #get rid of <ca> insertions.  CONFIRM??
    str_split_fixed(., " ", 3) %>% 
    as_tibble(.) %>% 
    mutate({{collate_col}}:=if_else(V2%in%{{remove_abbr}} | nchar(V2)<2,V1,paste0(V1," ",V2))) %>% 
    dplyr::select({{collate_col}}) %>%
    mutate({{collate_col}}:=gsub("[][]","",{{collate_col}})) %>% #get rid of square brackets.  CONFIRM??
    mutate({{collate_col}}:=gsub("[()]","",{{collate_col}})) %>% #get rid of parentheses.
  mutate({{collate_col}}:=sub(" [[:upper:]].*$","",{{collate_col}})) #get rid of suffixes starting with a captial letter
  df2<-df%>%dplyr::select(!{{collate_col}})
  cbind(df2,new)
}
#working example
species_abbreviations<-c("^sp_","^n_sp","sp","sp.","spp","spp.","spec","species","unknown","unk","unk.","NA",NA,"<NA>","","?","x","aff.","clone","partial","isolate","voucher","hybrid","(sect.","cf.")#when the species is not known, what takes its place?  Add to this as needed.
df1<-tibble(species=c("Homo sapiens","Homo sp","Homo spp","Homo unknown"," Homo sapiens","Homo sapiens "))
f_collate_names(df1,species,species_abbreviations)%>%unique()

# SPELLCHECK SCIENTIFIC NAMES: 
# f_spellcheck_sci_names
#It is easy to mispell scientific names (they are not in the Dictionary!). So this spellcheck function uses the taxize package, 
#but organizes the output in a more useful format.  The input should be a vector of unique taxon names (e.g., species). 
#Note that this can be slow because it needs to visit the internet to get the data it needs. 
#Provide an ENTREZ API key to make this go faster (you need to apply for this). 
#Because this function can take time to execute, it is recommended not to incorporate it into a larger file with other scripts. 
#Rather, execute it on a file and then save a new file with NCBI taxonomic ranks that can be uploaded and worked with.  
#Otherwise, it will be slow going. This function is primarily used to provide input to the function f_ranks_from_ids. 
#Note that if the output indicates a name change, it is important to confirm them before accepting them.
#
#options(ENTREZ_KEY = "......")#you need this for faster NCBI access (google it)

#THIS EXAMPLE WORKS
library(httr)
library(jsonlite)


#see advanced options at https://verifier.globalnames.org/ for a list of integers that correspond to databases to search
#1 = Catalogue of Life, 3 = Itis, 4 = NCBI, 9 = Worms, 11=GBIF

#' Spellcheck Scientific Names
#' @export
#' @examples
#' \dontrun{
#' f_spellcheck_sci_names(c("Hommo sapiens"), c(1, 4))
#' test_vec<-c("Nicidion cincta","Hipponix panamensis")
#' test_vec%>%f_spellcheck_sci_names(.,c(1,3,4,9,11))%>%View()#
#' }
f_spellcheck_sci_names <- function(input_names, database_codes) {
  if (!all(database_codes %in% c(1, 3, 4, 9, 11))) warning("Some database codes may not be recognized.")
  
  tryCatch({
    response <- httr::POST(
      url = "https://verifier.globalnames.org/api/v1/verifications",
      config = httr::add_headers(accept = "application/json", `Content-Type` = "application/json"),
      body = jsonlite::toJSON(list(nameStrings = input_names, dataSources = database_codes))
    )
    if (httr::http_error(response)) stop("API request failed")
    
    checked_names <- jsonlite::fromJSON(rawToChar(response$content))
    results <- dplyr::as_tibble(checked_names$names) %>%
      tidyr::unnest(cols = dplyr::everything(), names_sep = "_") %>%
      dplyr::select(dplyr::any_of(c(
        "name", 
        "bestResult_currentCanonicalSimple", 
        "bestResult_matchedName",
        "bestResult_classificationPath", 
        "bestResult_classificationRanks", 
        "dataSourcesIds"
      ))) %>%
      dplyr::rename(user_supplied_name = name) %>%
      # Use currentCanonicalSimple if available and not empty, otherwise use matchedName
      dplyr::mutate(
        spellchecked_names = dplyr::if_else(
          !is.na(bestResult_currentCanonicalSimple) & bestResult_currentCanonicalSimple != "",
          bestResult_currentCanonicalSimple,
          bestResult_matchedName
        )
      ) %>%
      dplyr::select(-dplyr::any_of(c("bestResult_currentCanonicalSimple", "bestResult_matchedName"))) %>%
      dplyr::mutate(name_change = dplyr::if_else(user_supplied_name == spellchecked_names, FALSE, TRUE)) %>%
      dplyr::ungroup() %>%
      dplyr::group_by(spellchecked_names) %>%
      dplyr::mutate(sources = paste0(unique(dataSourcesIds), collapse = ", ")) %>%
      dplyr::select(-dplyr::any_of("dataSourcesIds")) %>%
      dplyr::distinct() %>%
      dplyr::ungroup()
    return(results)
  }, error = function(e) stop(paste("Error in name verification:", e$message)))
}



test_vec<-c("Nicidion cincta","Hipponix panamensis")
test_vec%>%f_spellcheck_sci_names(.,c(1,3,4,9,11))%>%View()


## AVOID FATAL TIMEOUTS AND INCREASE SPEED WHEN SUBMITTING REQUESTS TO APIs
## f_submit_list_to_api
#This function is a wrapper that helps prevents fatal timeouts when requesting online information. It also tricks the api into not slowing things down.
#Dealing with taxonomic lists often requires a query to an online database. Sometimes this can be automated across a long list of queries. 
#Here is a function for applying a list to an api-query. A single api querty is simple, but we often want to submit request lists 
#rather than single requests. A long list may cause the api server to return an error, forcing you to start over.
#In this function, a request returns an error, rather than quitting or skipping the request, the function waits and submits that request again.  
#If it succeeds, it puts the output into a list. Often elements in the list may be complicated and so need to be processed. 
#Note that the input_vector will have NAs removed first. The cost to this function is that it then requires specific functions for each of the 
#potential taxonomic databases (see below). This is because it can only accept a name vector and a single input function. Someday I may generalize it.

#this is a function that allows many items to be passed to an api without crashing.
f_submit_list_to_api<-function(input_vector1,f_api_query){
  v1<-{{input_vector1}} %>% 
    subset(., !is.na(input_vector1)) %>%#remove NAs from the vector 
    unique()
  #These steps can mean the output is shorter than the input vector.
  for (j in 1:25) {#usually this resolves in one or two times. 25 trys should be more than enough to handle thousands of requests. 
    # Try evaluating the function
    try_result <- try(f_api_query(v1), silent = TRUE)
    # If no error occurred, return the result and exit loop
    if (!inherits(try_result, "try-error")) {
      break #exit the j loop if the try succeeds.
    }
    Sys.sleep(j)# for each failed try, increase the system sleep to give the server an increasingly long break.
  }
  return(try_result)
}

#simple. use if there is just a single database to be searched like worms.
f_submit_list_to_api(test_vec,taxize::get_wormsid)

x1<-get_wormsid("Girella nigricans")
#wrapper to allow options to be included.  E.g., the database to query might be an option in a query (e.g., taxize::get_ids_ has a db option)
f_robust_list_to_api <- function(input_vector1, f_api_query, ...) {
  # Wrap f_api_query with additional arguments
  wrapped_function <- function(v1) f_api_query(v1, ...)  # Bind arguments with :::
  
  # Call f_submit_list_to_api with the wrapped function
  f_submit_list_to_api(input_vector1, wrapped_function)
}

#working example AND compare the time to execute a spellcheck with and without the helper function.
long_name_vector<-c("Pulicaria glandulosa","Eucyclogobius newberryi","Girella nigricans","Pseudobatos productus","Bathyraja mariposa","Homo sapiens")#make a long species list to check

f_robust_list_to_api(long_name_vector, taxize::get_wormsid)

#HELP WORKING WITH TAXONOMIC HIERARCHIES: GENERALIZE
## f_generalize_taxonomy_ranks & f_ungeneralize_taxonomy_ranks
## A function to create generic taxonomy ranks and another to reverse the process.  E.g., rather than Species, the column name would be taxonomy_code_a.  This is required for some functions (and is embedded within them).  Otherwise, the functions here would only work with a single taxonomic ranking system.
#before using this function, you must indicate the names of the hierarchy rank columns in the ASV table in order from high to low.  These are the taxonomic column names used in the ASV table.Species is usually the last column.
#That list can be up to 11 names long. If your list is longer, you may need to modify the function.
#the input, df, is a filtered ASV table, with one row per hypothesized taxonomic assignment, columns representing a taxonomic hierarchy, This was changed in 9.1.
#and a column for the ASV number.
#
#Let's first define a vector called taxonomy_ranks which will correspond to column names in taxonomy tables. This is the system of ranks from high to low that one wishes to use.
#note that it is case sensitive.  In many cases, I suggest converting names like this to all lower case to avoid confusion.

#here are some examples.
KPCOFGS <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
kpcofgs <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
pcofgs <- c("phylum", "class", "order", "family", "genus", "species")
ofgs <- c("order", "family", "genus", "species")
#etc...

f_generalize_taxonomy_ranks <- function(df,taxonomy_ranks) {
  just_taxonomy <-df %>% 
    ungroup() %>%
    dplyr::select(all_of(rev(taxonomy_ranks)))
  remainder_df <- df %>% 
    ungroup() %>% 
    dplyr::select(!all_of(rev(taxonomy_ranks)))
  names(just_taxonomy) <- c(paste0("taxonomy_code_",letters[1:length(taxonomy_ranks)]))
  just_taxonomy[just_taxonomy == ""] <- NA
  #cbind(remainder_df,just_taxonomy) %>% unique()
  bind_cols(remainder_df,just_taxonomy)%>% distinct()
}

f_ungeneralize_taxonomy_ranks <- function(df,taxonomy_ranks) {#reverses the effect of f_generalize_taxonomy_ranks.  I.e., renames the 
  #df columns with the stated taxonomic hierarchy. Helpful after a function is used that requires a generalized hierarchy.
  df %>% rename_with(~ rev(taxonomy_ranks), paste0("taxonomy_code_",letters[1:length(taxonomy_ranks)]))
}


Ray_Data<-tibble(
  order=c("Mystery_order","Rhinopristiformes","Rhinopristiformes","Rhinopristiformes","Rhinopristiformes","Rhinopristiformes","Rajiformes","Torpedinidformes","Torpedinidformes","Torpedinidformes","Rajiformes"), 
  family=c("Mystery_family","Rhinobatidae","Rhinobatidae","Rhinobatidae","Rhinobatidae","Rhinobatidae","Rajidae","Torpedinidae","Torpedinidae","Torpedinidae","Gurgesiellidae"), 
  genus=c("Mystery_genus","Pseudobatos","Pseudobatos","Pseudobatos","Masterbatos","Pseudobatos", "Bathyraja","Tetronarce","Tetronarce","Tetronarce","Fenestraja"),
  species=c("Mystery_species","Pseudobatos productus",NA,"Pseudobatos productus","Masterbatos frequentis","Pseudobatos unproductus","Bathyraja mariposa",NA,NA,NA,"Fenestraja plutonia"),
  asv=c("a0","a1","a1","a1","a1","a1","a2","a3","a3","a3","a2"),
  perc_match=c(95,96,96,98,97,97,78,100,99,89,90),
  distribution=c("Distant","Frequent","Frequent","Frequent","Frequent","Frequent", "Regional", "Infrequent", "Infrequent", "Infrequent","Distant"))
#working example:compare these three tables.  
#Note, in particular, that the final table is similar to but not identical to the starting table.
Ray_Data
f_generalize_taxonomy_ranks(Ray_Data,ofgs) 
f_generalize_taxonomy_ranks(Ray_Data,ofgs) %>% f_ungeneralize_taxonomy_ranks(.,ofgs)


#BUILD TAXONOMIC HIERARCHIES FROM A LIST OF NAMES
#This function takes a list of latin names (of any rank), then queries a database to get updated taxonomic information and 
#the hierarchical classification for desired ranks.  It works with gbif, ncbi and worms, which must be entered in quotes.  
#It can take time for a long list. And the user may need to answer questions when there are many options to choose from. Practice with 
#a shortened version of the list (10 species) before running a list of hundreds.
#
#worms and gbif may have issues processing long lists. There may be value in doing 10 at a time.  Also
#they tend to struggle more with higher-rank taxa as these produce a large output (e.g., many species
#per genus).

#inputs 
#name_vector:a column-separated list of latin names of any taxonomic level.  c("Homo","Homo sapiens", "Cnidaria")
#taxonomy ranks: a vector of the taxonomic ranks that you want returned.  May be case sensitive (hint to use lc throughout)
#These must be in the taxonomic backbone you query. e.g., c("kingdom","phylum","class","order","family","genus","species").
#database: the online api source for taxonomic information based on taxize: use "ncbi" for sequence data, but also works with
#itis", "ncbi", "tropicos", "gbif", "nbn", or "worms".  Just one database entry in quotes. see taxize for more information.
taxon_list_to_taxon_hierarchy<-function(name_vector,taxonomy_ranks,database){
  
  id_name<-case_when(database=="ncbi"~ "uid",
                     database=="gbif"~ "usagekey",
                     database=="nbn" ~ "guid",
                     database=="itis" ~ "tsn",
                     database=="nbn" ~ "guid",
                     database=="tropicos" ~ "nameid")
  # Call the appropriate worms or ncbi/gbif function with the correct arguments
  
  if (database == "worms") {
    list_of_id_dfs<-name_vector%>%unique() %>%
      f_robust_list_to_api(.,taxize::get_wormsid,accepted=FALSE)#works
    input_ids<-tibble(submitted_name=name_vector%>%
                        unique(),id=list_of_id_dfs[1:length(name_vector%>%unique())])#note worms ID requires the name vector as input

  } else {
    # Pass both list_of_id_dfs and name_vector
    list_of_id_dfs<-name_vector%>%f_robust_list_to_api(.,taxize::get_ids_, db = database) #long_ids list
    input_ids<-bind_rows(list_of_id_dfs[[1]], .id = "submitted_name") %>%
      dplyr::select(submitted_name,!!id_name)%>%dplyr::rename(id=!!id_name)%>%as.tibble()
  }
  
  #should work for worms, ncbi & gbif
  long_ranks_list<-input_ids$id %>%
  f_robust_list_to_api(.,taxize::classification,db=database)#works
  
  #should work for worms, ncbi & gbif
  z<-tibble()
  for(i in 1:length({{long_ranks_list}})){
    id<-names(long_ranks_list)
    x<-long_ranks_list[[id[i]]]%>%dplyr::select(!id)%>%mutate(rank=rank%>%tolower())%>%filter(rank%in%taxonomy_ranks)
    y<-setNames(x$name, x$rank)
    z<-bind_rows(z,y)
  }
  taxonomic_df<-cbind(db=database,input_ids,z)%>%right_join(tibble(submitted_name=name_vector))
  print(taxonomic_df)
}

#working example.
vec1<-c("Cycloseris cyclolites","Lithophyllon repanda","Pocillopora capitata")
vec2<-c("Cocos nucifera","Pisonia grandis")


taxon_list_to_taxon_hierarchy(vec1,kpcofgs,"ncbi") 
taxon_list_to_taxon_hierarchy(vec2,kpcofgs,"tropicos") 
ncbidb<-taxon_list_to_taxon_hierarchy(long_name_vector,kpcofgs,"ncbi") #here I have added a species that is not in ncbi.

#CORRECT INCONSISTENCIES THAT ARISE IN TAXONOMIC HIERARCHIES
#Often there are some inconsistencies in the taxonomic hierarchy introduced by 
#combining different data sources. this could include different ranking systems
#or spelling errors.To have taxonomies play nicely, consistency is critical.
#But it is not always easy to spot inconsistencies in large tables.
#this code creates a table that identifies  inconsistencies in taxonomic hierarchies.
#It can later be edited in a way to create a consistent hierarchy.

##Note, does not correct species or genus mispellings. Just family and higher ranks
#the first step is to scan a dataframes for inconsistencies in higher ranks above genus.
#this simply finds cases where there is more than one higher rank per each lower rank.
#In such cases of inconsistency, only one can be correct.
#
#Start by doing a bind_rows on all the various taxonomic tables you will be working with.
#Use this combined table to identify inconsistencies within and among tables.
#from these inconsistencies generate a defined_multi_table.
#Apply the defined multi_table to correct each of the various taxonomic tables.
f_find_taxonomic_inconsistencies<-function(df,taxonomy_ranks){
  df_list<-list()
  for(i in 1:(length(taxonomy_ranks)-1)){
    df_list[[i]]<-df%>%#start with a taxonomic dataframe that might have other columns.
      select(taxonomy_ranks[i:(i+1)])%>%#for a table, just get the taxonomy for a rank and the one above it.
      filter(!is.na(!!sym(taxonomy_ranks[i+1])))%>%#remove rows with NAs
      unique()%>%#get unique associations
      group_by(!!sym(taxonomy_ranks[i+1]))%>%
      filter(n() > 1)%>%
      summarise(multi_upper_taxa = list(!!sym(taxonomy_ranks[i])))%>%
      mutate(rank=taxonomy_ranks[i+1])%>%dplyr::rename(lower_taxon=taxonomy_ranks[i+1])%>%as.tibble()%>%
      filter(lower_taxon!="")%>%
      filter(!is.na(lower_taxon))#needed?
  }
  bind_rows(df_list)%>%mutate(multi_list = sapply(multi_upper_taxa, toString))
}

#there is no way for code to know which of the inconsistent terminologies is correct.
#The user must inspect the multi_table
#E.G. multi_table$pick<-rep(2,nrow(multi_table))#user looks at the multi_table and creates a vector indicating which of the names to keep.  E,g., 1 always picks the first one.

##Next a function to apply the multitable to the orginal dataframe to correct the inconsistent spellings.
f_define_multi_table<-function(multitable,taxonomy_ranks){
  multitable$keep<-map2_chr(multitable$multi_upper_taxa, multitable$pick, ~ .x[.y])#define the multitable based on the user pick.
print(multitable)
  }

f_apply_multi_table<-function(df,multitable,taxonomy_ranks){
  nt<-length(taxonomy_ranks)
  for(i in 1:(nt-2)){
    df<-multitable%>%filter(rank==taxonomy_ranks[nt-i])%>%
      select(c(lower_taxon,keep))%>%
      dplyr::rename(!!sym(taxonomy_ranks[nt-i]):=lower_taxon)%>%
      right_join(df)%>%
      mutate(!!sym(taxonomy_ranks[nt-i-1]):= if_else(!is.na(keep),keep,!!sym(taxonomy_ranks[nt-i-1])))%>%select(!keep)
  }
  print(df)
  }

##WORKING EXAMPLE
Ray_Data_2<-
  tibble(order=c("Rhinoformes","Torpedinidformes"),
         family=c("Rhinobatidae","Torpedididae"),
         genus=c("Pseudobatos","Tetronarce"),
         species=c("Pseudobatos productus",NA))

bound_Ray_Data<-bind_rows(Ray_Data,Ray_Data_2)
#step one, make a table of inconsistent taxonomy use in a dataframe. More commonly, this
#will be a situation where there are multiple dataframes to check simultaneously. In that case, 
#use bind_rows to create an aggregate table for checking.

multi_table<-bound_Ray_Data%>%f_find_taxonomic_inconsistencies(.,ofgs)#
View(multi_table)

#step two, look at the multitable and create a vector of integers to indicate which 
#of the inconsistent names you want to replace the others with.
multi_table$pick<-c(1,1)#user looks at the multi_table and creates a vector indicating which of the names to keep.  E,g., 1 always picks the first one.
#note that this pick column is only valid for the current Ray_Data file. If that file changes in the 
#future, then a new pick column will be needed.

#Define the multi_table using the pick column. 
defined_multi_table<-f_define_multi_table(multi_table,ofgs)

#apply the defined multi table to Ray data to change inconsistencies as per the defined multi_table.
  f_apply_multi_table(Ray_Data_2,defined_multi_table,ofgs)
  
  #The corrected table for Ray_Data_2 now has the right family (Torpedinidae) and order (Rhinopristiformes)
  #
  f_apply_multi_table(Ray_Data,defined_multi_table,ofgs) # note that there were no corrections needed for Ray_Data.
  

#FIND THE FINEST RESOLUTION NAME FROM A HIERACHY TABLE OF TAXONOMIC RANKS
#f_create_taxon_name
## A  function to generate a taxon name column to represent the lowest rank in an uploaded dataframe.
# for each row, identify the lowest taxonomic rank, and put it in a column called taxon_name. This helps 
# identify a single name to use per row, which is important when determining a consensus taxonomy or taxon list.
f_create_taxon_name<-function(df,taxonomy_ranks){
  generalized_rank_list <- c(paste0("taxonomy_code_",letters[1:length(taxonomy_ranks)]))
  df %>% f_generalize_taxonomy_ranks(taxonomy_ranks)%>%
    mutate(taxon_name = coalesce(!!!syms(generalized_rank_list))) %>%
    f_ungeneralize_taxonomy_ranks(.,taxonomy_ranks)%>%
    rowwise() %>%
    mutate(taxon_name_rank = {
      # Extract the values for the current row across the specified columns
      values <- c_across(all_of(taxonomy_ranks))
      # Find the column name where the value matches new_column, if any
      matched_col <- taxonomy_ranks[which(values == taxon_name)[1]] 
      if (length(matched_col) == 0) NA_character_ else matched_col
    }) %>%
    ungroup()}

f_create_taxon_name(Ray_Data,ofgs) #note the 9.1 version gives taxon_name_rank instead of an integer.

#ELIMINATE HITS THAT ARE LIKELY ERRORS
#JV culls "unusual" hits as these are likely errors. They use a dominance threshold of 0.9.  E.g. JV keeps a taxon if it makes up 90% of the hits.
#Alternatively, a dominant hit might be one that has been sequenced a lot. So use a dominance filter with caution.
f_hit_dominance<-function(df,ID_col_name, taxonomy_ranks){
  #df2<-df %>%f_create_taxon_name(.,taxonomy_ranks)
  df%>%
    group_by({{ID_col_name}},taxon_name) %>%#within each asv and for each taxon_rank. {{}} and ".data[[col]]" are used to create text inputs from variable inputs
    summarize(frequency = n(),.groups = 'drop') %>% #count the number of times each hypothesized taxon is listed.  .groups = 'drop' is like ungroup within summarize.
    left_join(df %>%
                group_by({{ID_col_name}}) %>%
                summarize(hits = n(), .groups = 'drop'), #count the number of hits to a hypothesized taxon.  
              by = as_label(rlang::ensym(ID_col_name))) %>% #have to set the by variable (e.g., asv) to a text string
    mutate(dominance=(frequency / hits)) %>%
    group_by({{ID_col_name}}) %>%
    mutate(maxdominance=max(dominance)) %>%
    ##need to summarize...
    dplyr::select(!c(frequency,hits)) %>% left_join(.,df)
}

##Keep these hypotheses
Ray_Data%>%f_create_taxon_name(.,ofgs)%>%f_hit_dominance(.,asv,ofgs) %>% 
  filter(maxdominance<=.9 | dominance>=.9)#this particular example has no effect.

#Alternatively, Exclude these hypotheses
Ray_Data%>%f_create_taxon_name(.,ofgs)%>%f_hit_dominance(.,asv,ofgs) %>% 
  filter(maxdominance>=.9 & dominance<.9)#this particular example has no effect.



#SUMMARIZE AN ASV TABLE FOR PERCENT MATCH FOR SIMILAR HITS
## f_summarize_match
## In metabarcoding, it is common to get multiple hits to a single taxon_name (especially for well-studied species). 
## To avoid only selecting well-studied species as consensus, it helps to condense hypothesized matches to
## one row per taxon_name. In doing so, we need a summary statistic for some attributes like percent match. this could be max, median or mean.  I recommend the median, which is almost 
## usually equal to the maximum.  Doing so helps eliminate outliers caused by database errors.
##  f_summarize_match is a function to summarize a column (percent match or bitscore) per ASV - taxon_name combination
# calculate percent match statistics. Requires names for an ID column (asv), and a hypothesized taxon column (taxon_name), and a summary stat.

f_summarize_match <- function(df,ID_col_name,hypothesis_col_name,score_col_name,summary_stat) {
  enc_ID_col_name <- enquo(ID_col_name)#enquo the provided column name so it can be used as an object below.
  enc_hypothesis_col_name <- enquo(hypothesis_col_name)#enquo the provided column name so it can be used as an object below.
  enc_score_col_name <- enquo(score_col_name)#enquo the provided column name so it can be used as an object below.
  statistic_name<-enquo(summary_stat)
  
  new_name1  <- paste0(enquo(score_col_name))[2]# Rename so that median column name reflects score_col_name
  new_name2  <- paste0("max_",enquo(score_col_name))[2]# Rename so that max column name reflects score_col_name
  
  #create a list of stats per ID-taxon_name combo
  df1 <- df %>%
    ungroup() %>%
    group_by(!!enc_ID_col_name, !!enc_hypothesis_col_name) %>%
    summarise(SummaryMatch = {{summary_stat}}(!!enc_score_col_name)) %>%
    unique() %>% # calculate the median Perc Match for each species-ASV combo. this is NOT the median match across all the hits, it is the per taxon_name median match, which only an issue in cases when there are multiple hits to one taxon_name. Thus it only returns one row per taxon_name - asv combination.
    ungroup() %>% 
    mutate(summary_statistic=paste0(enquo(summary_stat)[2])) %>%
    group_by(!!enc_ID_col_name) %>%
    mutate(MaxMatch = max(SummaryMatch)) %>% # get the max PercMatch per an ASV.
    mutate(Match_Diff = MaxMatch - SummaryMatch) %>%
    mutate(Match_Rank = sapply(SummaryMatch, function(x) sum(SummaryMatch >= x)))
    #df1 <- df1 %>% rename({{ new_name1 }} := SummaryMatch,{{ new_name2 }} := MaxMatch) ##Failing now..
  
  df1 <- df1 %>% #replacement code.
    rename_at(vars("SummaryMatch"), function(x) new_name1) %>%
    rename_at(vars("MaxMatch"), function(x) new_name2)
  
  df %>% dplyr::select(-!!enc_score_col_name) %>%
    unique() %>%
    right_join(df1)
}

#working example
f_create_taxon_name(Ray_Data,ofgs) %>% 
  f_summarize_match(.,asv,taxon_name,perc_match,max)

#CREATE AN ORDINAL SCORE FROM A CATEGORICAL COLUMN.
#f_score_ordinal_col
#A function to generate an ordinal score, e.g., based on geography. This can be helpful for sorting or ranking.
#Here, ordination is used to score species according to their attributes in other columns.
#User must provides a list of the " as ordinal_col_ranks".
##these attributes are defined as ranks, which, when made into a vector, are given scores ordered from 1 to N.
#The ordinal column is entered in quotes.
f_score_ordinal_col <- function(df,ordinal_col_in_quotes,ordinal_col_ranks){
  newcolname <- paste0(ordinal_col_in_quotes,"_score")
  col1 <- df %>% pull(ordinal_col_in_quotes)
  df$factCol <- factor(col1,levels = ordinal_col_ranks)
  df %>% mutate(score_col = as.numeric(factCol)) %>%
    rename_at(vars("score_col"), function(x) newcolname) %>% 
dplyr::select(!factCol)
}
# working example
distribution_ranks <- c("Distant", "Regional", "Nearby", "Infrequent", "Frequent")
f_score_ordinal_col(Ray_Data,"distribution",distribution_ranks)

Ray_Data %>%
  f_create_taxon_name(.,ofgs) %>%
  f_score_ordinal_col(.,"taxon_name_rank",ofgs)


#Determine groups of asvs based on similarity.  Eg., used to inform redundancy before and during consensus.
library(Biostrings)     # For DNAStringSet and sequence handling
library(DECIPHER)       # For sequence alignment and distance matrix
library(dplyr)          # For data manipulation (optional, only if using pipes)

f_group_sequences <- function(input_sequences, prop_diff) {
  # Convert input to DNAStringSet
  if(is.character(input_sequences)) {
    seqs <- Biostrings::DNAStringSet(input_sequences)
  } else if(class(input_sequences) == "DNAStringSet") {
    seqs <- input_sequences
  } else {
    stop("Input must be character vector or DNAStringSet")
  }
  
  # Name the sequences if they're not named
  if(is.null(names(seqs))) {
    names(seqs) <- paste0("seq", 1:length(seqs))
  }
  
  # Align sequences
  aligned_seqs <- DECIPHER::AlignSeqs(seqs)
  
  # Calculate distance matrix
  dist_mat <- DECIPHER::DistanceMatrix(aligned_seqs)
  
  # Perform hierarchical clustering
  hc <- hclust(as.dist(dist_mat), method = "average")  # UPGMA
  
  # Cut tree to get clusters
  clusters <- cutree(hc, h = prop_diff)
  
  # Create output dataframe
  result <- data.frame(
    sequence_name = names(clusters),
    cluster = clusters,
    stringsAsFactors = FALSE
  )
  
  return(result)
}

asv1<-"TCTAGCTGGTAACTTAGCCCACGCAGGTTTGTCTGTCGACTTAGCTATTTGTTCGCTCCACTTAGCCGGTGTTTCTTCGATTTTAGGGGCTGTAAACTTTATTACCACGATTATTAATATACGATGACGAGGAATGCAATTTGAGCGGCTCCCTCTCTTCGTTTGATCGGTAAAAATTACTGCTGTCCTTCTTCTTCTCTCATTGCCAGTCTTGGCGGGTGCTATTACTATGCTCTTAACAGACCGAAACTTTAACACTGCCTTCTTTGATCCTGCGGGGGGTGGAGATCCTATTCTTTATCAGCATCTTTTT"
asv2<-"TTTAGCTGGTAACTTAGCCCACGCAGGGGGGTCTGTCGACTTAGCTATCTTCTCGCTCCACTTAGCCGGTGTTTCTCCGATTTTAGGGGCTGTAAACTTTATTACCACGATTATTAATATACGATGACGAGGAATGCAATTTGAGCGGCTCCCTCTCTTCGTTTGATCGGTAAAAATTACTGCTGTCCTTCTTCTTCTCTCATTGCCAGTCTTGGCGGGTGCTATTACTATGCTCTTAACAGACCGAAACTTTAACACTGCCTTCTTTGATCCTGCGGGGGGTGGAGATCCTATTCTTTATCAGCATCTTTTT"
asv3<-"TTTAGCTGGAATCTTAGCCCACGCAGGGGGGTCTGTCGACTTAGCTATTTTTTCGCTCCACTTAGCCGGTGTTTCTTCGATTTTAGGGGCTGTAAACTTTATTACCACGATTATTAATATACGATGACGAGGAATGCAATTTGAGCGGCTCCCTCTCTTCGTTTGATCGGTAAAAATTACTGCTGTCCTTCTTCTTCTCTCATTGCCAGTCTTGGCGGGTGCTATTACTATGCTCTTAACAGACCGAAACTTTAACACTGCCTTCTTTGATCCTGCGGGGGGTGGAGATCCTATTCTTTATCAGCATCTTTTT"
sequence_table1<-c(asv1,asv2,asv3)

Sp_Thresh_Match<-.98

f_group_sequences(sequence_table1,1-Sp_Thresh_Match)


#REDUCE REDUNDANCY
#
#f_filter_redundant_higher_hypotheses
#It is not uncommon to get unhelpful higher-rank hypotheses when other lower rank hypotheses are present.  E.g., Homo and Primate.
#Since we know Homo is a primate, we can simplify consensus by removing the primate row.
#We add a group column to distinguish cases where the redundant row is not redundant because it falls into a different group than
#the other similar taxa.  If ignored, group can be set to 1 throughout.  But if group is estimated from a distance matrix, 
#it will limit what is deemed redundant.
#Tends to remove rows with Taxonomic rank > 1. 
f_filter_redundant_higher_hypotheses <- function(df,ID_col_name,hypothesis_col_name,score_col_name,group_col_name,taxonomy_ranks) {
  enc_ID_col_name <- enquo(ID_col_name)#enquo the provided column name so it can be used as an object below.
  enc_hypothesis_col_name <- enquo(hypothesis_col_name)#enquo the provided column name so it can be used as an object below.
  enc_score_col_name <- enquo(score_col_name)#enquo the provided column name so it can be used as an object below.
  enc_group_col_name <- enquo(group_col_name)#enquo the provided column name so it can be used as an object below.
  df %>% ungroup() %>%
    group_by(!!enc_ID_col_name,!!enc_group_col_name) %>% #added group to grouping.
    summarise(Min_taxon_Rank = max(!!enc_score_col_name)) %>%
    ####
    unique() %>% # calculate the median Perc Match for each species-ASV combo.
    ungroup() %>%
    left_join(.,df) %>% 
    filter(Min_taxon_Rank==!!enc_score_col_name)%>%ungroup()
}

#working example that accounts for groups.
Ray_Data %>%mutate(group=c(1,2,3,2,4,5,6,7,7,8,9))%>%
  f_create_taxon_name(.,ofgs) %>%
  f_score_ordinal_col(.,"taxon_name_rank",ofgs) %>%
f_filter_redundant_higher_hypotheses(.,asv,taxon_name,taxon_name_rank_score,group,ofgs)

####

#add group information to hypothesized higher taxa.  This is relevant when we want to distinguish when a genus or a family taxon_name
#represents a single unknown species, or more than one.  Creates a new OTU column, which can replace taxon name during consensus if desired.

f_higher_taxon_groups<-function(df,hypothesis_col_name,score_col_name,group_col_name,taxonomy_ranks) {
  enc_hypothesis_col_name <- enquo(hypothesis_col_name)#enquo the provided column name so it can be used as an object below.
  enc_score_col_name <- enquo(score_col_name)#enquo the provided column name so it can be used as an object below.
  enc_group_col_name <- enquo(group_col_name)#enquo the provided column name so it can be used as an object below.
  
  df1<-df%>%filter(!!enc_score_col_name<length(taxonomy_ranks))
  #get hypotheses not to species.
  #
   Split_these<-df1%>%  
  select(!!enc_hypothesis_col_name,!!enc_group_col_name)%>%distinct()%>%
    group_by(!!enc_hypothesis_col_name)%>%
    summarize(.,count_groups=n())%>%
    filter(!count_groups==1)%>%pull(!!enc_hypothesis_col_name)
   
   df1%>%filter(!!enc_hypothesis_col_name%in%Split_these)%>% 
    
    ## pick the max rank of the matching rows
    mutate(OTU=paste0(!!enc_hypothesis_col_name," group_",!!enc_group_col_name))%>%
    right_join(.,df)%>%
    mutate(OTU=case_when(is.na(OTU)~taxon_name,
                         TRUE~OTU))
}

Ray_Data %>%mutate(group=c(1,2,3,2,4,5,6,7,7,8,9))%>%
  f_create_taxon_name(.,ofgs) %>%
  f_score_ordinal_col(.,"taxon_name_rank",ofgs) %>%
  f_higher_taxon_groups(.,taxon_name,taxon_name_rank_score,group,ofgs)%>%View()




#CONVERT COLUMN ENTRIES TO LISTS (e.g., hypothesized taxa for asvs) 
#f_list_hypotheses
#eDNA generates many hypothesized taxa, from which we choose a consensus, but we might want to keep track of the alternative hypotheses.
#this function counts the hypothesized taxa per ASV and also make an archive of the hypothesized taxa and pastes that into a separate column.
f_list_hypotheses <- function(df,ID_col_name,hypothesis_col_name) {
  df %>% dplyr::select({{ID_col_name}},{{hypothesis_col_name}}) %>% group_by({{ID_col_name}}) %>%
    unique() %>% #select just the most likely assignments. THIS GETS NS NON-LOCAL
    mutate(Hypotheses = paste0({{hypothesis_col_name}}, collapse = ", ")) %>% dplyr::select({{ID_col_name}},Hypotheses) %>% unique() %>% mutate(n_Hypotheses = 1 + str_count(Hypotheses, pattern = ","))
}
#working example
Ray_hypotheses<-Ray_Data %>% 
  f_create_taxon_name(.,ofgs) %>% unique() %>% 
  f_list_hypotheses(.,asv,taxon_name)
Ray_hypotheses
##FOR THIS FUNCTION, WE NEED TO ADJUST PROPMATCH IF THERE IS AN UPRANKING??
#FIND A CONSENSUS TAXON
#f_consensus_table:
#the input, df, is a filtered ASV table, with one row per hypothesized taxonomic assignment, columns representing a taxonomic hierarchy, 
#and a column for the ASV number.
#before using this function, you must indicate the names of the hierarchy rank columns in the ASV table in order from high to low.
## generate a consensus taxonomy from a dataframe that has a list of asvs each of which has a list of hypothesized taxonomic matches
## the grouping variable is the asv column, the rank list is the taxonomic ranks that are listed as columns.
## This function can handle up to 11 taxonomic ranks.
## NOTE changed taxonomy rank to rank rather than score.
#FIND A CONSENSUS TAXON
#f_consensus_table:
#the input, df, is a filtered ASV table, with one row per hypothesized taxonomic assignment, columns representing a taxonomic hierarchy, 
#and a column for the ASV number.
#before using this function, you must indicate the names of the hierarchy rank columns in the ASV table in order from high to low.
## generate a consensus taxonomy from a dataframe that has a list of asvs each of which has a list of hypothesized taxonomic matches
## the grouping variable is the asv column, the rank list is the taxonomic ranks that are listed as columns.
## This function can handle up to 11 taxonomic ranks.
f_consensus_table <- function(df,ID_col_name,taxonomy_ranks,score_col_name) {
  enc_score_col_name <- enquo(score_col_name)
  #best_col<-paste0("best_",enc_score_col_name)[[2]]
  dummycols <- matrix(nrow = 1, ncol = 11-length(taxonomy_ranks),"") %>%
    as.tibble(.) #create names for unused taxonomic ranks. (this function needs to work across a set number of columns- here 11 should cover most needs)
  names(dummycols) <- c(paste0("taxonomy_code_",letters[(length(taxonomy_ranks) + 1):11]))
  largedf<-df%>%
    f_create_taxon_name(.,taxonomy_ranks)%>%
    f_score_ordinal_col(.,"taxon_name_rank",taxonomy_ranks)%>%
    f_generalize_taxonomy_ranks(.,taxonomy_ranks) %>% #convert ranks to generics in the list below.
    cbind(.,dummycols) %>% #add some blank columns so that the case when below will not generate an error
    group_by({{ID_col_name}}) %>% #we want to pick one consensus per ASV.  Grouping by ASV does this.
    mutate(consensus = ifelse(!n_distinct(taxonomy_code_k, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_k)==0),NA,
                              ifelse(!n_distinct(taxonomy_code_j, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_j)==0),taxonomy_code_k,
                                     ifelse(!n_distinct(taxonomy_code_i, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_i)==0),taxonomy_code_j,
                                            ifelse(!n_distinct(taxonomy_code_h, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_h)==0),taxonomy_code_i,
                                                   ifelse(!n_distinct(taxonomy_code_g, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_g)==0),taxonomy_code_h,
                                                          ifelse(!n_distinct(taxonomy_code_f, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_f)==0),taxonomy_code_g,
                                                                 ifelse(!n_distinct(taxonomy_code_e, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_e)==0),taxonomy_code_f,
                                                                        ifelse(!n_distinct(taxonomy_code_d, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_d)==0),taxonomy_code_e,
                                                                               ifelse(!n_distinct(taxonomy_code_c, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_c)==0),taxonomy_code_d,
                                                                                      ifelse(!n_distinct(taxonomy_code_b, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_b)==0),taxonomy_code_c,
                                                                                             ifelse(!n_distinct(taxonomy_code_a, na.rm = TRUE)<2 | sum(!is.na(taxonomy_code_a)==0),taxonomy_code_b,
                                                                                                    taxonomy_code_a))))))))))))%>%
    mutate(consensus_rank =ifelse(!n_distinct(taxonomy_code_k, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_k)==0),NA,
                                  ifelse(!n_distinct(taxonomy_code_j, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_j)==0),11,
                                         ifelse(!n_distinct(taxonomy_code_i, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_i)==0),10,
                                                ifelse(!n_distinct(taxonomy_code_h, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_h)==0),9,
                                                       ifelse(!n_distinct(taxonomy_code_g, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_g)==0),8,
                                                              ifelse(!n_distinct(taxonomy_code_f, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_f)==0),7,
                                                                     ifelse(!n_distinct(taxonomy_code_e, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_e)==0),6,
                                                                            ifelse(!n_distinct(taxonomy_code_d, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_d)==0),5,
                                                                                   ifelse(!n_distinct(taxonomy_code_c, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_c)==0),4,
                                                                                          ifelse(!n_distinct(taxonomy_code_b, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_b)==0),3,
                                                                                                 ifelse(!n_distinct(taxonomy_code_a, na.rm = TRUE)<2| sum(!is.na(taxonomy_code_a)==0),2,
                                                                                                        1))))))))))))%>%
    #mutate(best = max({{enc_score_col_name}}))%>% #paste0("best_","enc_score_col_name")
    #mutate(best_score = paste0(enc_score_col_name)[[2]])%>% #paste0("best_","enc_score_col_name")
    mutate(best:= max({{enc_score_col_name}}))
  smalldf<-largedf%>%
    mutate(taxon_score=1+length(taxonomy_ranks)-taxon_name_rank_score)%>%
    mutate(best_rank=taxon_name_rank)%>%
    filter(best=={{enc_score_col_name}})%>%
    filter(taxon_score==max(taxon_score))%>%
    select({{enc_score_col_name}},taxon_score,best_rank)
  largedf%>%left_join(.,smalldf)%>%
    select(c({{ID_col_name}},consensus,consensus_rank,{{enc_score_col_name}},best_rank,taxon_score))%>%
    distinct()%>%
    filter(!is.na(consensus))%>%
    filter(!is.na(best_rank))%>%
    mutate(LCA_upranked=ifelse(consensus_rank>taxon_score,TRUE,FALSE))#return three columns used for the final consensus table.
}

Ray_Data%>%f_consensus_table(.,asv,ofgs,perc_match)

Sp_Thresh_Match <- .98
Gen_Thresh_Match <-.95
Fam_Thresh_Match<-.90
Order_Thresh_Match<-.85 #?
Class_Thresh_Match<-.75 #?
Phylum_Thresh_Match<-.50 #?

thresh_table=tibble(taxon=c("species","genus","family","order","class","phylum"),threshold=c(Sp_Thresh_Match,Gen_Thresh_Match,Fam_Thresh_Match,Order_Thresh_Match,Class_Thresh_Match,Phylum_Thresh_Match))
thresh_table2<-bind_cols(thresh_table%>%select(taxon),bind_rows(tibble(threshold=1),thresh_table%>%select(threshold))%>%dplyr::slice(.,1:(nrow(thresh_table))))
thresh_table3<-left_join(thresh_table,thresh_table2,by ="taxon")%>%
  f_score_ordinal_col(.,"taxon",pcofgs)
names(thresh_table3)<-c("taxon_name_rank","min_thresh","max_thresh","taxon_name_rank_score")

Ray_Data%>%f_consensus_table(.,asv,ofgs,perc_match)%>%
  mutate(propmatch=perc_match/100)%>% #requires converting to proportion.
  left_join(thresh_table3%>%mutate(consensus_rank=row_number()))%>%
  mutate(adj_propmatch=ifelse(!LCA_upranked,propmatch,pmin(1,propmatch/max_thresh)))

#GET A UNIQUE LIST ALL TAXA FROM ALL LEVELS.
#f_taxa_list_from_df
#R function that gets a list of all taxonomic terms from a dataframe. 
#E.g., a list of all the taxonomic terms associated with a filtered dataframe.  
#This is helpful when categorizing entries in consensus table as likely or not likely.  
#Specifically, I use it to generate lists of likely or unlikely taxa.
## 
f_taxa_list_from_df <- function(df,taxonomy_ranks){
  df1 <- df %>% ungroup() %>%
    select_if(names(.) %in% taxonomy_ranks) %>% #  
    stack() %>%
    pull(values) %>%
    unique()
  df1[!is.na(df1)]#gets rid of NAs
}

#working example
f_taxa_list_from_df(Ray_Data,ofgs)

#IDENTIFY OPTIMAL MATCH CUTOFF FOR A SPECIES, GENUS, and FAMILY.
#f_rank_threshold
##It is common to use arbitrary cut off values to determine confidence to a species (98%) or genus (95%).
##But with a sufficienly large validation data set, it is possible to estimate these thresholds directly.
##Find a non-arbitrary cutoff for assigning a hypothesis to a particular taxonomic rank using validation data. 
##One can use this as a threshold when filtering by scores. Returns a single value.
f_rank_threshold<-function(df,tax_rank,ID_col_name,score_col_name,LikelyList){
  x<-df %>% 
    filter({{tax_rank}} %in% LikelyList) %>% # just keep the likely taxa for the rank of interest.
    dplyr::select(!{{ID_col_name}}) %>% unique() %>% # keep unique hypothesized assignments
    group_by(taxon_name) %>% # here I pick the highest score per taxon name. Although this allows at least one valid taxon to be kept, it might not keep all of them. This will increase the threshold
    summarise(Max=max({{score_col_name}})) %>% #e.g., pick % match or a bit score.
    pull(Max) %>% quantile(0) 
  x[[1]]
}

#working example.

#First generate a dataframe with observations
Ray_Data2 <- Ray_Data %>% 
  f_create_taxon_name(.,ofgs) %>% 
  f_summarize_match(.,asv,taxon_name,perc_match,median) %>%
  f_score_ordinal_col(.,"distribution",distribution_ranks) %>%
  group_by(taxon_name) %>% mutate(maxscorepertaxon = max(distribution_score)) %>%
  filter(distribution_score == maxscorepertaxon)

TaxonDistributionTable<-c()

PlausibleList<-c("Pseudobatos productus","Tetronarce californica","Pseudobatos") # requires a plausible list for validation.

#could not get lapply to work well, so one function per taxon rank.
Sp_Thresh <-f_rank_threshold(Ray_Data2,species,asv,perc_match,PlausibleList)
All_Thresh<-f_rank_threshold(Ray_Data2,taxon_name,asv,perc_match,PlausibleList)
Sp_Thresh
All_Thresh


#QUALITY CONTROL FOR POOR MATCHES
#f_reduce_poor_match_specificity
#A consensus may point to a single species, even with a low percent match.  This could be due to low sequence coverage.
#Rather than filter out poor matches, we can lower their consensus to a higher taxonomic rank 
#(e.g., keep the genus rather than the species if the match is poor)
#Min et al do this after consensus. But I suggest doing it before.
#Ideally, the thresholds are determined with validation data as done by the f_rank_threshold function.

#a function that will change the rank at which a taxon is specified based on whether the quality of the match to the reference
#exceeds a threshold. This function makes poorly matched hypotheses less specific, thereby reducing false positives.  For eDNA
#It it typically done at the Species and Genus ranks based on thresholds like 98% and 95% match, respectively.

##Redo with a threshold TABLE??
f_reduce_poor_match_specificity<-function(df,tax_rank,score_col_name,score_threshold){
  rankenc <- enquo(tax_rank)
  score_col_nameenc <- enquo(score_col_name)
  #scoreenc <- enquo(score_col_name)
  df %>% 
    mutate(uprank_from := if_else({{score_col_name}} < score_threshold,taxon_name_rank,NA))%>%#create a column indicating the initial taxon_rank
    mutate(uprank_from := if_else(uprank_from=={{tax_rank}},NA,uprank_from))%>% #but only keep this value if the rank changes.
    mutate(!!rankenc := if_else({{score_col_name}} < score_threshold,NA,{{tax_rank}})) #if you are below a threshold for that rank, enter NA.
}



#working example
Sp_Thresh<-97
#
Ray_Data2 %>% 
  f_reduce_poor_match_specificity(.,species,perc_match,Sp_Thresh) %>%
  f_create_taxon_name(.,ofgs)%>%View() #because % match for Bathyraja mariposa
#was low, this removes the species epithet, reducing the chance that we will assume precision we don't have.

#here is an example of thresholding taxonomic rank by geography..
Ray_Data2 %>% 
  f_reduce_poor_match_specificity(.,species,distribution_score,3)%>%View()

#here is an example of thresholding, but keeping the old data for posterity. 
Ray_Data2 %>%
mutate(original_taxon_name=taxon_name) %>% # create a column to keep the original taxon_name.
  mutate(original_taxon_name_rank=taxon_name_rank) %>% # create a column to keep the original taxon_name_rank.
  f_reduce_poor_match_specificity(.,species,perc_match,Sp_Thresh) %>% # remove non-confident assignments..
  mutate(original_taxon_name=original_taxon_name) %>% #fill in the new column with the original
  mutate(original_taxon_name_rank=original_taxon_name_rank) %>% #fill in the new column with the original
  f_create_taxon_name(.,ofgs) #write over the original with a new taxon_name.



#ASSIGN DISTANT SPECIES TO LOCAL RELATIVES
#f_local_relatives
#Most filtering is easy.But re-assigning a hypothesis to its closest relative is hard and deserves its own function.
# Find species that are on an implausible list. Replace them with "plausible" relatives
# The extent of the replacement will depend on the most local taxonomic rank.
# Invasive species should not be Implausible and should be NotImplausible.

##Method options = "none" (do not execute),"any" (consider sequenced and unsequenced),"unsequenced" (consider unsequenced only),"priority" (consider sequenced only if there are no unsequenced options)
f_local_relatives<-function(df, Implausible_list,NotImplausibleHierarchy, taxonomy_ranks,Method){
  genNIHdf<-NotImplausibleHierarchy%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks) %>% #generalize a hierarchy of not implausible taxa and 
    
    ##NEW
    filter(case_when(Method== "unsequenced" ~ !sequenced,# don't include sequenced
                     Method== "none" ~ FALSE, #include none
                     Method== "priority" ~ TRUE, #count and filter later 
                     Method== "any" ~ TRUE))####
  
  
  df1<-df%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks) #generalize a asv dataframe with hierarchy
  gentaxlist<-df%>%ungroup()%>%dplyr::select(all_of(taxonomy_ranks))%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks)%>%names()# a list of teh taxon ranks.
  dflist<-list() #empty list to fill
  replacements<-c()
  for (i in 1:(length(taxonomy_ranks)-1)) { #repeate loop across all the taxon ranks except the highest.
    column_name<-gentaxlist[i] #start at the lowest taxon rank, and repeat for higher ones.
    column_name_other<-setdiff(gentaxlist,gentaxlist[i+1]) #ranks that are not the rank being evaluated.
    dflist[[i]]<-df1 %>% filter(get(column_name) %in% Implausible_list) %>% #get rows where that taxonomy rank is implausible.
      dplyr::rename(oldtaxon_name=taxon_name) %>% #define that as the old taxon name.
      #rename_at(vars("oldcol"), function(x) newcolname) #model fix
      #rename_at(vars(taxon_name), function(x) oldtaxon_name) %>% #fixed
      dplyr::select(!c(!!column_name_other))%>% #delete the other taxon ranks.
      dplyr::select(!any_of(c("sequenced")))%>%#some columns if present in the ASVfile and genNIHdf will mess with inner join.  Delete them.
      inner_join(.,genNIHdf,relationship = "many-to-many") %>% # fill in with one or more not implausible taxa
      mutate(replacement="yes")%>%ungroup()%>% ##define the row as having been replaced.
      group_by(oldtaxon_name)%>%
      mutate(count_unsequenced = sum(!sequenced))%>% ungroup()%>%####NEW
      filter(case_when(Method== "priority" & count_unsequenced>0 ~ !sequenced,
                       TRUE ~ TRUE))
    
    if (length(dflist[[i]]$oldtaxon_name) == 0) {
      replacements<-c(replacements,"empty")  # Replace with your preferred default value if one exists.
    } else {
      replacements<-c(replacements, dflist[[i]]$oldtaxon_name)
    }
    #make a list of names that have been replaced. This will be used next to remove the rows that have been replaced
  }
  replacements<-replacements%>%as_tibble()%>%filter(!value=="empty")%>%pull(value)
  
  implausible_df<-df1 %>% #the original datframe
    #rows that are going to be replaced.
    bind_rows(.,bind_rows(dflist)) %>%
    filter(if_any(gentaxlist, ~ (.x %in% Implausible_list)))
  
  repaired_df<-df1 %>% #the original datframe
    #filter(!taxon_name%in%Implausible_list) %>% # remove rows that are going to be replaced.
    bind_rows(.,bind_rows(dflist)) %>%
    filter(!if_any(gentaxlist, ~ (.x %in% Implausible_list)))%>%
    #now bind with the replacement rows.
    f_ungeneralize_taxonomy_ranks(.,taxonomy_ranks) %>%
    dplyr::select(!c(taxon_name,taxon_name_rank)) %>%
    f_create_taxon_name(.,taxonomy_ranks)
  
  #some implausible rows were not repaired. 
  unrepaired_df<-implausible_df%>%filter(taxon_name%in%setdiff(implausible_df$taxon_name,repaired_df$oldtaxon_name))%>%
    #now bind with the replacement rows.
    f_ungeneralize_taxonomy_ranks(.,taxonomy_ranks) %>%
    dplyr::select(!c(taxon_name,taxon_name_rank)) %>%
    f_create_taxon_name(.,taxonomy_ranks)
  
  bind_rows(repaired_df,unrepaired_df)#combine repaired and unrepaired rows.
}
Implausible_list1<-c("Mystery_species","Bathyraja mariposa","Masterbatos frequentis","Masterbatos","Fenestraja plutonia","Fenestraja","Gurgesiellidae")#need a list of geographically implausible taxa that can be replaced with plausible possibilities. should include all taxononmic levels..
NotImplausibleList1<-c("Pseudobatos productus","Tetronarce californica","Pseudobatos","Bathyraja aleutica") # this will be the list of potential replacement relatives. It can be broader than the plausible list.
#need to create a hierarchy for the NotImplausibleList.  Should include Invasives list!
NotImplausibleHierarchy1<-NotImplausibleList1 %>% taxon_list_to_taxon_hierarchy(.,ofgs,"ncbi")%>%dplyr::select(all_of(ofgs))%>%
  mutate(sequenced=c(FALSE,FALSE,FALSE,TRUE))%>%f_create_taxon_name(.,ofgs)#for the left join with the asv table, the Hierarchy should only contain taxon ranks.


f_local_relatives(Ray_Data2, Implausible_list1,NotImplausibleHierarchy1, ofgs,"any")%>%View()


#IDENTIFY LIKELY AND UNLIKELY CONSENSUS
#f_consensus_likelihood
#A consensus algorithm can easily settle on an error, such as an out of range species.  We can identify these unlikely hypotheses
#for additional scrutiny and reconsideration.
## : A function to determine which consensus entries appear to be Unlikely (use this if Unlikely taxa have been scored).
## a function to generate a list of plausible or implausible taxa from dataframes. Inputs are a consensus table and two lists two dataframes.  One with plausible taxa. The other with implausible taxa.
#Identify which consensus taxa are associated with likely (=1) or unlikely (=0) taxa. Uncertain returns NA.
#The user supplies the two lists.
#E.g., species seen nearby (or invasive) might be considered likely whereas species not seen regionally (and non invasive) might be considered 
#Unlikely.Or the users applies local knowledge or expertise to develop the list. Lists should include various taxonomic ranks (e.g., not just species).
f_consensus_likelihood <- function(df,LikelyList, UnlikelyList,EvalCol) {
  var<-enquo(EvalCol)
  df %>% ungroup %>% mutate(likelihood = case_when(
    df%>%pull(!!var) %in% LikelyList ~ 1,
    df%>%pull(!!var) %in% UnlikelyList ~ 0)
  )
}
## 
PlausibleList <- c("Pseudobatos","Pseudobatos productus","Torpedo", "Torpedo californica")
Implausible_list<-c("Bathyraja mariposa","Masterbatos frequentis","Masterbatos","Fenestraja plutonia","Fenestraja","Gurgesiellidae")
#apply the function
Ray_Data2 %>% f_consensus_likelihood(.,PlausibleList,Implausible_list,taxon_name)%>%dplyr::select(taxon_name,distribution_score, maxscorepertaxon, likelihood)
#one can use this to generate statistical relationships between plausibility and variuos species attributes like distribution scores.
## 




#a function that runs a function based on a condition.  Useful for iterating across a list of conditions and other conditional applications.
#Depending on the condition, return one output or the other. If TRUE, the consensus is returned. If false, the raw data is returned.  But it could be something else.
# Define the generic function to apply one of the above functions based on a condition.  If the condition is false, return the dataframe unaltered
f_conditional_run <- function(condition, df, func1, ...) {
  if (condition) {
    return(func1(df, ...))
  } else {
    return(df)
  }
}
#working example. Note that sometimes function inputs may need to be in quotes.
Apply_funct<-5>3 #some kind of condition with TRUE FALSE outcome
Ray_Data%>%f_conditional_run(
  condition=Apply_funct,
  func1=f_consensus_table,#function name
  ID_col_name=asv,#function input 1
  taxonomy_ranks=ofgs,#function input 2
  score_col_name=perc_match#function input 3 etc.
)


##Choosing a more plausible option AFTER consensus. Could combine to a single function??
# two functions that downranks a table 1 that has a consensus column using information
# from second table 2 that has ranks columns.
# 
# Requires a sequenced column in the Plausible_Table. There are four options for how sequencing is considered.
f_downrank<-function(Consensus_df,ID_col_name,score_col_name,NotImplausibleHierarchy,taxonomy_ranks,Method){
  quo_ID_col_name<-enquo(ID_col_name)
  quo_score_col_name<-enquo(score_col_name)
  genNIHdf<-NotImplausibleHierarchy%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks) %>% #generalize a hierarchy of not implausible taxa and 
    
    ##NEW
    filter(case_when(Method== "unsequenced" ~ !sequenced,# don't include sequenced
                     Method== "none" ~ FALSE, #include none
                     Method== "priority" ~ TRUE, #count and filter later 
                     Method== "any" ~ TRUE))####
  
  gentaxlist<-seq(1:length(taxonomy_ranks))## a list of the taxon ranks.
  dflist<-list() #empty list to fill
  for (i in 1:(length(taxonomy_ranks)-1)) { 
    #column_name<-gentaxlist[i] #start at the lowest taxon rank, and repeat for higher ones.
    #column_name_other<-setdiff(gentaxlist,gentaxlist[i+1]) #ranks that are not the rank being evaluated.
    rank1<-c("taxonomy_code_a","taxonomy_code_b","taxonomy_code_c","taxonomy_code_d","taxonomy_code_e","taxonomy_code_f","taxonomy_code_g","taxonomy_code_h","taxonomy_code_i","taxonomy_code_j")[1:length(taxonomy_ranks)][(length(taxonomy_ranks)+1-i)]#
    dflist[[i]]<-Consensus_df%>%ungroup()%>% filter(consensus_rank==gentaxlist[(length(taxonomy_ranks)+1-i)])%>% #Identify taxa to be downtranked
      #rename(!!rank1:=consensus)%>%#
      #rename_at(vars("oldcol"), function(x) newcolname) #model fix
      rename_at(vars(consensus), function(x) rank1)%>% #fixed
      select(!any_of(c("taxon_name","taxon_name_rank","taxon_score")))%>%
      left_join(.,genNIHdf)%>%#add lower plausible ranks.
      na.omit()%>%
      mutate(replacement="yes")%>%ungroup()%>% ##define the row as having been replaced.
      group_by(!!quo_ID_col_name)%>%
      mutate(count_unsequenced = sum(!sequenced))%>% ungroup()%>%####NEW
      filter(case_when(Method=="priority" & count_unsequenced>0 ~ !sequenced,
                       TRUE~TRUE))%>%ungroup()
  }
    df1<-bind_rows(dflist)%>%f_ungeneralize_taxonomy_ranks(.,taxonomy_ranks)
  
  ##If there are downranked taxa, generate a new consensus.
  f_conditional_run(nrow(df1)>0,df1,f_consensus_table, ID_col_name = !!quo_ID_col_name, taxonomy_ranks = taxonomy_ranks,score_col_name=!!quo_score_col_name)%>%  
    bind_rows(.,Consensus_df)%>%group_by(!!quo_ID_col_name)%>%
    filter(!is.na(consensus))%>%
    filter(consensus_rank==min(consensus_rank))%>%distinct()
}

#see inputs above from f_local_relatives.
f_consensus_table(Ray_Data,asv,ofgs,perc_match)%>%
  f_downrank(.,asv,perc_match,NotImplausibleHierarchy1,ofgs,"any")%>%View()

f_consensus_table(Ray_Data,asv,ofgs,perc_match)%>%
  f_downrank(.,asv,perc_match,NotImplausibleHierarchy1,ofgs,"none")%>%View()

#expandTaxonDistributionTable and
#update_upranked_likelihood

##Expand a taxon distribution table compiled mostly at the species level to add 
##rows for each higher taxon rank.  E.g., if you have a row for a species, make a separate row for
## the genus, family, etc.This is helpful when we want to create a table that includes rows for
##  each of the higher ranks present in a table. For instance after upranking, or after doing
##  a consensus taxonomy that results in upranking, we might want to add taxonomic hierarchies back
##  to the dataframe. Expanding the taxonomic distribution table automates this step. Note that
##  when expanding a taxondistribution table, there may be columns like likelihood or sequenced, that 
##are different for higher ranks than the rank they came from. An additional function (below) is needed
## to correct this.
## 
## Input: 1) a taxon distribution table with a column indicating expected abundance/occupancy.
##            and taxon columns, and a taxon_name column
##        2) taxonomy_ranks (kpcofgs)
## Output: a dataframe that has added rows for higher taxon ranks.
## 
##  
f_expandTaxonDistributionTable<-function(InitialTaxonDistributionTable,taxonomy_ranks){
  gentaxlist<-InitialTaxonDistributionTable%>%ungroup()%>%dplyr::select(all_of(taxonomy_ranks))%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks)%>%names()#fix kpcofgs
  dflist<-list()
  for (i in 1:(length(taxonomy_ranks)-1)){
    dflist[[1]]<-InitialTaxonDistributionTable%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks)%>%mutate(taxon_name_rank='taxonomy_code_a')
    dflist[[i+1]]<-InitialTaxonDistributionTable%>%f_generalize_taxonomy_ranks(.,taxonomy_ranks)%>%
      dplyr::select(-gentaxlist[1:i])%>%
      mutate(taxon_name=get(gentaxlist[i+1]),taxon_name_rank=gentaxlist[i+1])%>%unique()
  }
  bind_rows(dflist)%>%#left_join(.,tibble(new_taxon_name_rank=taxonomy_ranks,taxon_name_rank=rev(gentaxlist)))%>%
    dplyr::select(!any_of(c("taxon_name_rank","taxon_name")))%>%
    f_ungeneralize_taxonomy_ranks(.,taxonomy_ranks)%>%
    f_create_taxon_name(.,taxonomy_ranks)
}

#after expanding a taxondistribution table, there may be columns like likelihood or sequenced, that 
#are different for higher ranks than the rank they came from. This code evaluates likelihood for 
#higher ranks as the maximum likelihood that the taxon_name holds for any lower rank. This is likely 
#conservative and might deserve manual updating in some cases.
#
#Inputs: 1) an expanded taxon distribution table as produced by f_expandTaxonDistributionTable.
#           this dataframe should have taxonomic ranks as columns in addition, you will need
#           a likelihood (factor) column and a likelihood_score (integer) column.  The likelihood score column can
#           be created from the likelihood colummn using the f_score_ordinal_col function.
#       2) a character vector of distribution ranks in order of low to high score.
#       
#Output: an expanded taxon distribution table with updated distribution ranks.
f_update_upranked_likelihood<-function(ExpandedTaxonDistributionTable,distribution_ranks)
{ExpandedTaxonDistributionTable%>%
    #determine the likelihoods for the newly generated higher ranks.  
    filter(!is.na(taxon_name))%>%
    group_by(across(-all_of(c("likelihood","likelihood_score"))))%>%
    summarize(likelihood_score=max(likelihood_score))%>%unique() %>% #keep the highest likelihood achieved by a lower rank.
    mutate(likelihood = case_when(likelihood_score==5 ~ distribution_ranks[5], #put likelihood back in (reverse engineer)
                                  likelihood_score==4 ~ distribution_ranks[4],
                                  likelihood_score==3 ~ distribution_ranks[3],
                                  likelihood_score==2  ~ distribution_ranks[2],
                                  likelihood_score==1  ~ distribution_ranks[1]))%>%ungroup()
}

##working example.
f_score_ordinal_col(Ray_Data,"distribution",distribution_ranks)%>%
  f_create_taxon_name(.,ofgs)%>%
  #dplyr::select(-c(asv,perc_match))%>%
  dplyr::select(!any_of(c("asv","perc_match")))%>%
  dplyr::rename(likelihood=distribution)%>%
  dplyr::rename(likelihood_score=distribution_score)%>%
  f_expandTaxonDistributionTable(.,ofgs)%>%
  f_update_upranked_likelihood(.,c("Distant", "Regional", "Nearby", "Infrequent", "Frequent"))%>%View()

#search_sequence_by_gene
#search ncbi for the number of sequences associated with a taxon name. Handy for figuring out whether one should 
#expect a hit to a reference database. dates must be in quotes and be in YYYY/MM/DD format (just year is fine).  e.g., "2000" or "2000/01/12"
#also, organize multiple gene names as a list.  See below for an example.
f_search_sequence_by_gene<-function(GeneNames,InputSpeciesList,startdate,enddate){
  Genelable<-rep(NA,length(GeneNames))#set up an empty vector to make a set of text labels for each gene
  for(g in 1:length(GeneNames)){Genelable[g]<-GeneNames[[g]][1]}#label the genes based on the first synonym you entered
  sequencecount<-tibble(species=rep(InputSpeciesList, each = length(GeneNames)),gene=rep(Genelable,length(InputSpeciesList)), count=NA)#make an empty dataframe with a row for each gene-species combination.
  #For each species, search through the list of genes to search for and report back the number of sequences at NCBII
  for(j in 1:length(InputSpeciesList)){
    for(i in 1:length(GeneNames)){
      a <- GeneNames[[i]]
      b <- rep("OR",length(a)-1)
      x <- vector(class(a), length(c(a, b)))
      x[c(TRUE, FALSE)] <- a
      ifelse(length(a)>1,x[c(FALSE, TRUE)] <- b,x)
      y<-na.omit(x)
      geneoptions<-paste(y,collapse=" ")
      searchterm<-paste(InputSpeciesList[j],
                        "AND",
                        "(",geneoptions,")",
                        "AND",
                        "(",startdate,"[PDAT] : ",enddate,"[PDAT])" #can be year.
      )
      sequencecount$count[i+(j-1)*(length(GeneNames))]<-f_robust_list_to_api(searchterm, entrez_search, 
                                                                             db = "nuccore",
                                                                             retmax = 100,  # maximum returns, Adjust retmax as needed 
      )$count #this is a GITA function that helps handle long lists.
    }
    print(j/length(InputSpeciesList))}#show progress
  pivot_wider(sequencecount,names_from = gene,values_from=count)#restructure the data with genes as columns.
}


#Example nucleotides to search for as well as their possible synonyms.
Names_Co1<-c("Coi","Co1","Coxi","Cox1")#
#Names_CYTB<-c("CYTB")
Names_12S<-c("12S","RRNS")
#Names_16S<-c("16S","RRNL")
Names_18S<-c("18S")
#Names_its<-c("its")
#Names_rcbL<-c("rcbL")
#Names_ND2<-c("ND2")
#Names_ND4<-c("ND4")

#working example: count 12 sequences per species
Ray_Data %>% 
  f_create_taxon_name(.,ofgs)%>%
  pull(taxon_name)%>%
  unique()%>%
  f_search_sequence_by_gene(Names_12S,.,"1990","2020")
f_search_sequence_by_gene(list(Names_12S,Names_Co1),c("Gambusia affinis","Fundulus parvipinnis"),"2020","2025")

f_search_sequence_by_gene(list(Names_12S,Names_18S),c("Clinocardium nuttallii"),"1990","2025")



