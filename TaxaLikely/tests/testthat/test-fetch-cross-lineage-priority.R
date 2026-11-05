# End-to-end tests for WHERE the cross-lineage contamination filter runs.
#
# A unit test of the resolver cannot fail under the shipped placement: call it
# directly and it filters whatever list it is handed. The defect is the
# PLACEMENT -- fetch.R runs it on `all_meta`, the broad-search rows only, before
# the priority-species rows are bound in -- so a priority-species homonym is
# never judged and never votes. These tests drive
# fetch_ncbi_reference_sequences() far enough to bind both paths together.
#
# Fully offline, and they write NOTHING: cache_dir = NULL makes
# .ref_cache_file() return NULL (fetch.R:863), so no cache file is read or
# written and the real reference cache is untouched. The three network entry
# points are mocked.
#
# dry_run = TRUE stops before any FASTA download, and the decided placement is
# before the dry-run return, so the dry run is the cheapest place to observe the
# filtered set. Its `sequences` table carries `acc`, which is what lets these
# assert by accession rather than by count.

# Two organisms share the genus name Ulvaria: a stichaeid fish (Ulvaria
# subbifurcata, the shanny) and a green alga. Both are plausible in a
# California intertidal study, so neither can be resolved by assuming scope.
LINEAGE <- list(
  T_FISH = c(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
             order = "Perciformes", family = "Stichaeidae", genus = "Ulvaria",
             species = "Ulvaria subbifurcata"),
  T_ALGA = c(kingdom = "Viridiplantae", phylum = "Chlorophyta", class = "Ulvophyceae",
             order = "Ulvales", family = "Monostromataceae", genus = "Ulvaria",
             species = "Ulvaria obscura"),
  T_SEB  = c(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
             order = "Perciformes", family = "Sebastidae", genus = "Sebastes",
             species = "Sebastes mystinus"),
  T_GIR  = c(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
             order = "Perciformes", family = "Kyphosidae", genus = "Girella",
             species = "Girella nigricans"),
  T_FUN  = c(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri",
             order = "Cyprinodontiformes", family = "Fundulidae", genus = "Fundulus",
             species = "Fundulus parvipinnis"),
  # For the negative control: a genuinely multi-kingdom fetch.
  T_ULVA = c(kingdom = "Viridiplantae", phylum = "Chlorophyta", class = "Ulvophyceae",
             order = "Ulvales", family = "Ulvaceae", genus = "Ulva",
             species = "Ulva lactuca"),
  T_FUNG = c(kingdom = "Fungi", phylum = "Ascomycota", class = "Dothideomycetes",
             order = "Pleosporales", family = "Pleosporaceae", genus = "Alternaria",
             species = "Alternaria alternata")
)

# acc -> taxid, so every fixture row's organism is declared in one place.
make_rows <- function(spec) {
  data.frame(
    acc = names(spec), acc_version = paste0(names(spec), ".1"),
    title = paste(names(spec), "12S ribosomal RNA gene"),
    taxid = unname(spec), slen = 400,
    organism = vapply(unname(spec), function(t) LINEAGE[[t]][["species"]], character(1L)),
    create_date = "2026/08/29", stringsAsFactors = FALSE
  )
}

# The taxonomy map the fetch would get from NCBI, for whatever ranks it asks
# for. Asking for a rank NCBI would not return is not simulated here: every
# taxid in these fixtures has every rank, so a missing `class` column in the
# result means the CALLER did not request it.
fake_tax_map <- function(taxids, ranks) {
  taxids <- unique(as.character(taxids))
  out <- data.frame(taxid = taxids, stringsAsFactors = FALSE)
  for (r in ranks) {
    out[[r]] <- vapply(taxids, function(t) {
      v <- LINEAGE[[t]]
      if (!is.null(v) && r %in% names(v)) v[[r]] else NA_character_
    }, character(1L))
  }
  out
}

# `fixtures` maps a taxon name to its acc->taxid spec. The mocks dispatch on the
# search term, which carries the taxon name.
local_fetch_mocks <- function(fixtures, counts, env = parent.frame()) {
  which_taxon <- function(term) {
    hit <- names(fixtures)[vapply(names(fixtures),
      function(n) grepl(n, term, fixed = TRUE), logical(1L))]
    # Longest match wins: "Ulvaria subbifurcata" contains "Ulvaria".
    if (length(hit) == 0L) NA_character_ else hit[which.max(nchar(hit))]
  }
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax = 0L, use_history = FALSE, config = NULL, ...) {
      tx <- which_taxon(term)
      n <- if (is.na(tx)) 0L else counts[[tx]]
      list(count = n, term = term, web_history = NULL)
    },
    .package = "rentrez", .env = env
  )
  testthat::local_mocked_bindings(
    .fetch_summaries_batched = function(search_obj, batch_size = 200L) {
      tx <- which_taxon(search_obj$term)
      if (is.na(tx)) return(NULL)
      make_rows(fixtures[[tx]])
    },
    .fetch_taxonomy_map = function(taxids, ranks, ...) fake_tax_map(taxids, ranks),
    # .ncbi_delay() takes no arguments and its RETURN VALUE is the sleep
    # duration (fetch.R:1769 -> Sys.sleep(delay)), so it must return a number,
    # not NULL. Returning 0 makes every sleep a no-op.
    .ncbi_delay = function() 0,
    .package = "TaxaLikely", .env = env
  )
}


test_that("a priority-species homonym is filtered, and the fish rows are kept by accession", {
  skip_if_not_installed("rentrez")

  fixtures <- list(
    # The priority species returns BOTH organisms under the one name.
    "Ulvaria subbifurcata" = c(PFISH1 = "T_FISH", PFISH2 = "T_FISH",
                               PALGA1 = "T_ALGA", PALGA2 = "T_ALGA"),
    "Sebastes"  = c(SEB1 = "T_SEB"),
    "Girella"   = c(GIR1 = "T_GIR"),
    "Fundulus"  = c(FUN1 = "T_FUN")
  )
  counts <- list("Ulvaria subbifurcata" = 4L, Sebastes = 4L, Girella = 4L, Fundulus = 4L)
  local_fetch_mocks(fixtures, counts)

  out <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = c("Sebastes", "Girella", "Fundulus"),
    barcode_term = "12S", rank_system = c("family", "genus", "species"),
    priority_taxa = "Ulvaria subbifurcata",
    max_sequences = 1L, min_len = 100L, max_len = 5000L,
    cache_dir = NULL, dry_run = TRUE
  ))

  accs <- out$sequences$acc

  # Fixture sanity FIRST: if the budget allocation ever starves the broad path,
  # or the priority branch stops being reached, the behavioural assertions below
  # would pass for the wrong reason. Three single-organism broad taxa are also
  # exactly what min_context = 3 needs.
  expect_true(all(c("SEB1", "GIR1", "FUN1") %in% accs),
    info = "broad-search context rows missing: the fixture, not the filter, is wrong")
  expect_true(any(grepl("^P", accs)),
    info = "no priority rows reached the assembly: the priority branch was not taken")

  # The defect: the alga rows arrive under a priority species, so the shipped
  # placement never judges them.
  expect_false(any(c("PALGA1", "PALGA2") %in% accs))
  # And the fix must not resolve the homonym by discarding the whole name.
  expect_true(all(c("PFISH1", "PFISH2") %in% accs))
})


test_that("a homonym arriving ONLY through the priority path is still filtered", {
  skip_if_not_installed("rentrez")

  fixtures <- list(
    "Ulvaria subbifurcata" = c(PALGA1 = "T_ALGA", PALGA2 = "T_ALGA", PFISH1 = "T_FISH"),
    "Sebastes" = c(SEB1 = "T_SEB"),
    "Girella"  = c(GIR1 = "T_GIR"),
    "Fundulus" = c(FUN1 = "T_FUN")
  )
  counts <- list("Ulvaria subbifurcata" = 3L, Sebastes = 4L, Girella = 4L, Fundulus = 4L)
  local_fetch_mocks(fixtures, counts)

  out <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = c("Sebastes", "Girella", "Fundulus"),
    barcode_term = "12S", rank_system = c("family", "genus", "species"),
    priority_taxa = "Ulvaria subbifurcata",
    max_sequences = 1L, min_len = 100L, max_len = 5000L,
    cache_dir = NULL, dry_run = TRUE
  ))
  accs <- out$sequences$acc

  expect_true(all(c("SEB1", "GIR1", "FUN1") %in% accs))
  expect_false(any(c("PALGA1", "PALGA2") %in% accs))
  expect_true("PFISH1" %in% accs)
})


test_that("nothing is dropped when no organism group reaches the dominance bar", {
  skip_if_not_installed("rentrez")

  # A genuinely multi-kingdom fetch: animal, plant and fungus, with one split
  # taxon. No group reaches 90%, so the filter must decline.
  fixtures <- list(
    "Ulvaria subbifurcata" = c(PFISH1 = "T_FISH", PALGA1 = "T_ALGA"),
    "Sebastes" = c(SEB1 = "T_SEB"),
    "Ulva"     = c(ULV1 = "T_ULVA"),
    "Alternaria" = c(ALT1 = "T_FUNG")
  )
  counts <- list("Ulvaria subbifurcata" = 2L, Sebastes = 4L, Ulva = 4L, Alternaria = 4L)
  local_fetch_mocks(fixtures, counts)

  out <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = c("Sebastes", "Ulva", "Alternaria"),
    barcode_term = "12S", rank_system = c("family", "genus", "species"),
    priority_taxa = "Ulvaria subbifurcata",
    max_sequences = 1L, min_len = 100L, max_len = 5000L,
    cache_dir = NULL, dry_run = TRUE
  ))
  accs <- out$sequences$acc

  expect_true(all(c("SEB1", "ULV1", "ALT1") %in% accs))
  # Both halves of the split taxon survive: with no dominant group there is no
  # reference organism to judge them against.
  expect_true(all(c("PFISH1", "PALGA1") %in% accs))
})
