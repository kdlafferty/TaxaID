.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
devtools::load_all("TaxaTools", quiet = TRUE); devtools::load_all("TaxaAssign", quiet = TRUE)
D <- "/Users/lafferty/My Drive/Stats and Data/GreatLakes data"; P <- "GreatLakes2023BurnsHarbor_v103finalb"
cf <- readRDS(file.path(D, paste0(P,"_consensus_final.rds")))
pu <- readRDS(file.path(D, paste0(P,"_posteriors_updated.rds")))
S <- attr(cf, "consensus_settings")   # the saved call's own settings (species_reference, group_priors included)
out <- character(); say <- function(...) { l <- sprintf(...); cat(l, "\n"); out <<- c(out, l) }
is_eth <- function(x) !is.na(x) & (x == "Etheostoma" | startsWith(x, "Etheostoma "))
pl_has <- vapply(cf$plausible_taxa, function(v) any(is_eth(unlist(v))), logical(1))
pl_all <- vapply(cf$plausible_taxa, function(v) { v <- unlist(v); length(v) > 0 && all(is_eth(v)) }, logical(1))
touched <- is_eth(cf$consensus_taxon)
say("units in consensus_final: %d", nrow(cf))
say("settings used: %s", paste(names(S)[!names(S) %in% c("species_reference","group_priors","taxonomy_cache_dir")],
    vapply(S[!names(S) %in% c("species_reference","group_priors","taxonomy_cache_dir")], function(z) paste(z, collapse="/"), ""), sep="=", collapse="; "))
say("  plus species_reference (%dx%d) and group_priors (%dx%d) taken from attr(consensus_final,'consensus_settings'); lookup_missing_taxonomy overridden to FALSE; taxonomy_cache_dir NULL",
    nrow(S$species_reference), ncol(S$species_reference), nrow(S$group_priors), ncol(S$group_priors))
say("touched by call (consensus_taxon Etheostoma*): %d", sum(touched))
say("units whose plausible_taxa contains Etheostoma*: %d ; of which call is not Etheostoma*: %d ; plausible set ALL Etheostoma*: %d",
    sum(pl_has), sum(pl_has & !touched), sum(pl_all))
say("rank of touched calls: %s", paste(names(table(cf$consensus_rank[touched])), table(cf$consensus_rank[touched]), sep="=", collapse=", "))
touch_ids <- cf$observation_id[touched | pl_has]
say("units rerun as 'touched set' (call OR plausible): %d", length(touch_ids))

run <- function(ids) {
  a <- S[setdiff(names(S), c("lookup_missing_taxonomy","taxonomy_cache_dir"))]
  set.seed(1)
  do.call(posterior_consensus, c(list(pu[pu$observation_id %in% ids, , drop = FALSE]), a, list(lookup_missing_taxonomy = FALSE)))
}
cmp <- function(res, ids, grp) {
  m <- merge(data.frame(observation_id = ids, group = grp),
    cbind(res[, c("observation_id","consensus_taxon","consensus_rank")]), by = "observation_id", all.x = TRUE)
  names(m)[3:4] <- c("new_taxon","new_rank")
  s <- cf[match(m$observation_id, cf$observation_id), c("consensus_taxon","consensus_rank")]
  m$saved_taxon <- s$consensus_taxon; m$saved_rank <- s$consensus_rank
  m$match <- (m$new_taxon %in% m$saved_taxon & m$new_taxon == m$saved_taxon | (is.na(m$new_taxon) & is.na(m$saved_taxon))) &
             (m$new_rank == m$saved_rank | (is.na(m$new_rank) & is.na(m$saved_rank)))
  m$match[is.na(m$match)] <- FALSE
  m
}
r1 <- run(touch_ids)
t1 <- cmp(r1, touch_ids, ifelse(touch_ids %in% cf$observation_id[touched], "touched_call", "touched_plausible_only"))
say("TOUCHED reproduction: %d / %d match on consensus_taxon+rank", sum(t1$match), nrow(t1))
if (any(!t1$match)) for (i in which(!t1$match)) say("  MISMATCH %s: new %s [%s] vs saved %s [%s]", t1$observation_id[i], t1$new_taxon[i], t1$new_rank[i], t1$saved_taxon[i], t1$saved_rank[i])
# step 3
er <- pu[pu$observation_id %in% touch_ids & is_eth(pu$taxon_name), ]
say("Etheostoma posterior rows in touched units: %d ; NA class: %d ; NA order: %d ; NA family: %d ; NA phylum: %d ; distinct class values: %s",
    nrow(er), sum(is.na(er$class)), sum(is.na(er$order)), sum(is.na(er$family)), sum(is.na(er$phylum)), paste(unique(er$class), collapse="/"))
er_all <- pu[is_eth(pu$taxon_name), ]
say("Etheostoma posterior rows in whole file: %d ; NA class: %d", nrow(er_all), sum(is.na(er_all$class)))
rk <- c(species=1, genus=2, family=3, order=4, class=5, phylum=6, kingdom=7)
coarse <- pl_all & rk[cf$consensus_rank] > 2
say("units with plausible set all Etheostoma* but call coarser than genus: %d %s", sum(coarse, na.rm=TRUE), paste(cf$observation_id[which(coarse)], collapse=","))
coarse2 <- pl_has & !touched & rk[cf$consensus_rank] > 2
say("units with Etheostoma* in plausible set, call not Etheostoma*, coarser than genus: %d", sum(coarse2, na.rm=TRUE))
if (any(coarse2, na.rm=TRUE)) { w <- which(coarse2); for (i in w) say("  %s call=%s [%s] plausible=%s", cf$observation_id[i], cf$consensus_taxon[i], cf$consensus_rank[i], paste(unlist(cf$plausible_taxa[[i]]), collapse=" | ")) }
# controls
set.seed(1)
pool <- setdiff(cf$observation_id, touch_ids)
ctl <- sample(pool, 200)
r2 <- run(ctl)
t2 <- cmp(r2, ctl, "control")
say("CONTROL reproduction: %d / %d identical on consensus_taxon+rank", sum(t2$match), nrow(t2))
if (any(!t2$match)) for (i in which(!t2$match)) say("  MISMATCH %s: new %s [%s] vs saved %s [%s]", t2$observation_id[i], t2$new_taxon[i], t2$new_rank[i], t2$saved_taxon[i], t2$saved_rank[i])
write.csv(rbind(t1, t2), "homonym_validation/gl_units.csv", row.names = FALSE)
writeLines(out, "homonym_validation/gl_results.txt")
