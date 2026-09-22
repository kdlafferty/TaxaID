# Tests for R/setup.R -- workflow_check(), sniff_input(), and the
# requires/requirements.json contract. Offline only: every test that calls
# workflow_check() sets options(TaxaWizard.offline = TRUE) so the "network"
# category is skipped rather than making a real HTTP call, and restores the
# option on exit so it cannot leak into other test files.

.tw_offline <- function(expr) {
  old <- options(TaxaWizard.offline = TRUE)
  on.exit(options(old), add = TRUE)
  force(expr)
}


# ==============================================================================
# requirements.json / requires contract
# ==============================================================================

test_that("requirements.json loads and has the expected top-level shape", {
  req <- TaxaWizard:::.load_requirements()
  expect_type(req, "list")
  expect_true(all(c("keys", "packages", "binaries", "network", "groups") %in% names(req)))
  expect_true(length(req$keys) > 0L)
  expect_true(length(req$packages) > 0L)
  expect_true(length(req$binaries) > 0L)
  expect_true(length(req$network) > 0L)
})

test_that("every edge in workflow_graph.json has a requires field", {
  graph <- TaxaWizard:::.load_graph()
  expect_true(length(graph$edges) >= 30L)
  for (edge in graph$edges) {
    expect_true("requires" %in% names(edge), info = edge$id)
  }
})

test_that("every requires token is defined in requirements.json (key/net/bin groups or ids)", {
  graph <- TaxaWizard:::.load_graph()
  req <- TaxaWizard:::.load_requirements()

  key_ids <- vapply(req$keys, function(k) k$id, character(1))
  group_ids <- paste0("key:", names(req$groups))
  net_ids <- vapply(req$network, function(n) n$id, character(1))
  bin_ids <- vapply(req$binaries, function(b) b$id, character(1))
  pkg_ids <- vapply(req$packages, function(p) p$id, character(1))
  known <- c(key_ids, group_ids, net_ids, bin_ids, pkg_ids)

  all_tokens <- unique(unlist(lapply(graph$edges, function(e) e$requires)))
  # net:llm / net:gbif are implied by workflow_check() itself (not literal
  # edge tokens), but they must still resolve, so include them explicitly.
  all_tokens <- union(all_tokens, c("net:llm", "net:gbif"))

  unknown <- setdiff(all_tokens, known)
  expect_equal(unknown, character(0))
})

test_that("TAXAID_PACKAGES lists the 8 documented packages", {
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  expect_equal(pkgs, c(
    "TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
    "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag"
  ))
})


# ==============================================================================
# workflow_check()
# ==============================================================================

test_that("workflow_check() returns a taxaid_check data.frame with the documented columns", {
  out <- .tw_offline(TaxaWizard::workflow_check(verbose = FALSE))
  expect_s3_class(out, "taxaid_check")
  expect_s3_class(out, "data.frame")
  expect_named(out, c("component", "category", "status", "detail", "fix"))
  expect_true(all(out$category %in% c("r", "package", "key", "network", "cache", "binary")))
  expect_true(all(out$status %in% c("ok", "missing", "warn", "skip")))
})

test_that("workflow_check() never includes a key VALUE in detail/fix, only set/unset", {
  # Sys.setenv a fake, distinctive value and confirm it never appears verbatim.
  old <- Sys.getenv("ANTHROPIC_API_KEY", unset = NA)
  Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-TOTALLY-SECRET-VALUE-12345")
  on.exit({
    if (is.na(old)) Sys.unsetenv("ANTHROPIC_API_KEY") else Sys.setenv(ANTHROPIC_API_KEY = old)
  }, add = TRUE)

  out <- .tw_offline(TaxaWizard::workflow_check(verbose = FALSE))
  text_blob <- paste(out$detail, out$fix, collapse = "\n")
  expect_false(grepl("TOTALLY-SECRET-VALUE", text_blob, fixed = TRUE))
})

test_that("workflow_check(edges = 'seq_to_match') narrows to NCBI/BLAST, not GBIF", {
  out <- .tw_offline(TaxaWizard::workflow_check(edges = "seq_to_match", verbose = FALSE))

  key_net_bin <- out[out$category %in% c("key", "network", "binary"), , drop = FALSE]
  expect_true(any(grepl("^net:ncbi$", key_net_bin$component)))
  expect_true(any(grepl("^key:ENTREZ_KEY$", key_net_bin$component)))
  expect_true(any(grepl("^bin:blastn$", key_net_bin$component)))

  expect_false(any(grepl("^net:gbif$", key_net_bin$component)))
  expect_false(any(grepl("^key:gbif$", key_net_bin$component)))

  # r/package/cache categories are unconditional -- still present.
  expect_true("r" %in% out$category)
  expect_true("package" %in% out$category)
})

test_that("workflow_check(edges = 'taxa_to_occ') shows GBIF, not NCBI/BLAST", {
  out <- .tw_offline(TaxaWizard::workflow_check(edges = "taxa_to_occ", verbose = FALSE))
  key_net_bin <- out[out$category %in% c("key", "network", "binary"), , drop = FALSE]

  expect_true(any(grepl("^net:gbif$", key_net_bin$component)))
  expect_true(any(grepl("^key:gbif$", key_net_bin$component)))
  expect_false(any(grepl("^net:ncbi$", key_net_bin$component)))
  expect_false(any(grepl("^bin:blastn$", key_net_bin$component)))
})

test_that("workflow_check(edges = character(0) of offline-only edges) still reports r/package/cache", {
  out <- .tw_offline(TaxaWizard::workflow_check(edges = "match_to_taxa", verbose = FALSE))
  expect_true(all(c("r", "package", "cache") %in% out$category))
  key_net_bin <- out[out$category %in% c("key", "network", "binary"), , drop = FALSE]
  expect_equal(nrow(key_net_bin), 0L)
})

test_that("workflow_check() warns and drops unknown edge ids rather than erroring", {
  expect_warning(
    out <- .tw_offline(TaxaWizard::workflow_check(edges = "not_a_real_edge", verbose = FALSE)),
    "unknown edge"
  )
  expect_true("r" %in% out$category)
})

test_that("workflow_check() rejects a bad 'edges' argument", {
  expect_error(TaxaWizard::workflow_check(edges = 1L), "character vector")
  expect_error(TaxaWizard::workflow_check(edges = character(0)), "character vector")
})

test_that("network rows are status 'skip' under TaxaWizard.offline", {
  out <- .tw_offline(TaxaWizard::workflow_check(edges = "taxa_to_occ", verbose = FALSE))
  net_rows <- out[out$category == "network", , drop = FALSE]
  expect_true(nrow(net_rows) > 0L)
  expect_true(all(net_rows$status == "skip"))
})

test_that("print.taxaid_check() runs without error and returns its input invisibly", {
  out <- .tw_offline(TaxaWizard::workflow_check(verbose = FALSE))
  expect_output(ret <- print(out), "TaxaWizard setup check")
  expect_identical(ret, out)
})

test_that("workflow_check(verbose = TRUE) prints automatically", {
  expect_output(
    .tw_offline(TaxaWizard::workflow_check(edges = "match_to_taxa", verbose = TRUE)),
    "TaxaWizard setup check"
  )
})


# ==============================================================================
# sniff_input()
# ==============================================================================

.tw_sniff_dir <- function() {
  dir <- file.path(tempdir(), sprintf("taxawizard-sniff-%s", basename(tempfile())))
  dir.create(dir, recursive = TRUE)
  dir
}

test_that("sniff_input() classifies a plain FASTA as sequences", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "asvs.fasta")
  writeLines(c(">ASV_001", "ACGTACGTACGTACGTACGT", ">ASV_002", "TTGGCCAATTGGCCAATTGG"), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "sequences")
  expect_equal(out$confidence, "high")
})

test_that("sniff_input() classifies a FASTA + composite_id taxonomy sibling as local_fasta", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "refs.fasta")
  writeLines(c(">ACC001", "ACGTACGTACGT"), f)
  tax <- file.path(dir, "refs.tsv")
  writeLines(c("composite_id\tfamily\tgenus\tspecies", "ACC001\tGobiidae\tEucyclogobius\tnewberryi"), tax)

  out <- sniff_input(f)
  expect_equal(out$node_id, "local_fasta")
  expect_equal(out$confidence, "high")
})

test_that("sniff_input() classifies a headerless CRABS TSV as local_fasta", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "crabs_db.tsv")
  row <- paste(
    c(
      "ACC123.1", "1;2;3", "9606", "Animalia", "Chordata", "Actinopteri",
      "Perciformes", "Gobiidae", "Eucyclogobius", "Eucyclogobius newberryi",
      "ACGTACGTACGTACGTACGTACGTACGT"
    ),
    collapse = "\t"
  )
  writeLines(row, f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "local_fasta")
})

test_that("sniff_input() classifies a DADA2 seqtab .rds as sequences", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "seqtab.rds")
  seqs <- c(
    "ACGTACGTACGTACGTACGTACGTACGTACGT",
    "TTGGCCAATTGGCCAATTGGCCAATTGGCCAA"
  )
  mat <- matrix(c(10L, 0L, 3L, 7L), nrow = 2, dimnames = list(c("sample1", "sample2"), seqs))
  saveRDS(mat, f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "sequences")
  expect_equal(out$confidence, "high")
})

test_that("sniff_input() classifies a BirdNET CLI CSV as birdnet_detections", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "recording.BirdNET.results.csv")
  writeLines(c(
    "Start (s),End (s),Scientific name,Common name,Confidence",
    "0.0,3.0,Corvus brachyrhynchos,American Crow,0.92"
  ), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "birdnet_detections")
  expect_equal(out$confidence, "high")
})

test_that("sniff_input() classifies R-mangled BirdNET headers as birdnet_detections", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "combined.csv")
  writeLines(c(
    "Start..s.,End..s.,Scientific.name,Common.name,Confidence,File",
    "0.0,3.0,Corvus brachyrhynchos,American Crow,0.92,rec1.wav"
  ), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "birdnet_detections")
})

test_that("sniff_input() classifies an Animl long-format CSV as image_classifier_output", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "animl_results.csv")
  writeLines(c(
    "FileName,prediction,confidence",
    "img001.jpg,Odocoileus virginianus,0.93"
  ), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "image_classifier_output")
})

test_that("sniff_input() classifies an iNaturalist CV JSON as image_classifier_output", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "IMG_001.json")
  writeLines(
    '{"results":[{"combined_score":72.4,"score":68.1,"taxon":{"name":"Danaus plexippus","rank":"species"}}]}',
    f
  )

  out <- sniff_input(f)
  expect_equal(out$node_id, "image_classifier_output")
  expect_equal(out$confidence, "high")
  expect_match(out$evidence, "iNaturalist")
})

test_that("sniff_input() classifies a SpeciesNet predictions_json as image_classifier_output", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "predictions.json")
  writeLines(
    paste0(
      '{"predictions":[{"filepath":"IMG_001.jpg",',
      '"classifications":{"classes":["u1;amphibia;anura;bufonidae;rhinella;marina;cane toad"],"scores":[0.87]},',
      '"prediction":"u1;amphibia;anura;bufonidae;rhinella;marina;cane toad","prediction_score":0.87}]}'
    ),
    f
  )

  out <- sniff_input(f)
  expect_equal(out$node_id, "image_classifier_output")
  expect_match(out$evidence, "SpeciesNet")
})

test_that("sniff_input() classifies a lat/lon CSV as occurrences", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "occ.csv")
  writeLines(c(
    "scientificName,decimalLatitude,decimalLongitude,eventDate",
    "Fundulus parvipinnis,34.41,-119.86,2024-05-01"
  ), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "occurrences")
})

test_that("sniff_input() classifies a score + rank CSV as match_df", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "match.csv")
  writeLines(c(
    "observation_id,score,family,genus,species",
    "ASV_001,97.4,Gobiidae,Eucyclogobius,newberryi"
  ), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "match_df")
})

test_that("sniff_input() classifies a single name column as taxa", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "species_list.csv")
  writeLines(c("species", "Eucyclogobius newberryi", "Clevelandia ios"), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "taxa")
})

test_that("sniff_input() classifies a rank-only, no-score, observation-level CSV as consensus_df", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "consensus.csv")
  writeLines(c(
    "observation_id,family,genus,species,site,date",
    "S1,Gobiidae,Eucyclogobius,newberryi,PtCon,2024-05-01"
  ), f)

  out <- sniff_input(f)
  expect_equal(out$node_id, "consensus_df")
})

test_that("sniff_input() returns NA with evidence for a nonexistent file", {
  out <- sniff_input(file.path(tempdir(), "does_not_exist_at_all.csv"))
  expect_true(is.na(out$node_id))
  expect_true(nzchar(out$evidence))
})

test_that("sniff_input() returns NA with evidence for an empty file, never errors", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "empty.csv")
  file.create(f)

  expect_error(out <- sniff_input(f), NA)
  expect_true(is.na(out$node_id))
})

test_that("sniff_input() never errors on binary garbage", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "garbage.bin")
  writeBin(as.raw(sample(0:255, 500, replace = TRUE)), f)

  expect_error(out <- sniff_input(f), NA)
  expect_true(is.character(out$evidence))
})

test_that("sniff_input() does not misclassify an arbitrary .R script as a single-column taxon list", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "build_fixture.R")
  writeLines(c(
    "# =========================================================",
    "# A helper script, not a data file -- no delimiter on line 1",
    "library(TaxaTools)"
  ), f)

  out <- sniff_input(f)
  expect_true(is.na(out$node_id))
})

test_that("sniff_input() rejects a bad path argument without erroring", {
  expect_error(out <- sniff_input(NA_character_), NA)
  expect_true(is.na(out$node_id))
  expect_error(out2 <- sniff_input(character(0)), NA)
  expect_true(is.na(out2$node_id))
})

test_that("sniff_input() sniffs a directory from its first (or BirdNET-like) file, downgrading confidence", {
  dir <- .tw_sniff_dir()
  writeLines(c(
    "Start (s),End (s),Scientific name,Common name,Confidence",
    "0.0,3.0,Corvus brachyrhynchos,American Crow,0.92"
  ), file.path(dir, "rec1.BirdNET.results.csv"))
  writeLines("not a birdnet file", file.path(dir, "readme.txt"))

  out <- sniff_input(dir)
  expect_equal(out$node_id, "birdnet_detections")
  expect_equal(out$confidence, "medium") # downgraded from "high"
})

test_that("all node ids sniff_input() can return are real input node ids in the graph", {
  possible_ids <- TaxaWizard:::.list_node_types()$inputs
  dir <- .tw_sniff_dir()

  fixtures <- list(
    sequences = c(">a", "ACGTACGTACGTACGT"),
    taxa = c("species", "Eucyclogobius newberryi"),
    occurrences = c("decimalLatitude,decimalLongitude", "34.4,-119.8"),
    match_df = c("observation_id,score,genus,species", "S1,90,Gobius,paganellus"),
    consensus_df = c("observation_id,genus,species,site", "S1,Gobius,paganellus,PtCon"),
    birdnet_detections = c(
      "Start (s),End (s),Scientific name,Common name,Confidence",
      "0.0,3.0,Corvus brachyrhynchos,American Crow,0.92"
    )
  )
  for (nm in names(fixtures)) {
    f <- file.path(dir, paste0(nm, ".csv"))
    writeLines(fixtures[[nm]], f)
    out <- sniff_input(f)
    if (!is.na(out$node_id)) {
      expect_true(out$node_id %in% possible_ids, info = nm)
    }
  }
})


# --- P6: rendering setup state into prompts -----------------------------------

test_that(".format_check_block() reports only rows that need attention", {
  chk <- data.frame(
    component = c("R version", "key:ENTREZ_KEY", "bin:blastn"),
    category  = c("r", "key", "binary"),
    status    = c("ok", "warn", "missing"),
    detail    = c("4.5.2", "unset", "not on PATH"),
    fix       = c("", "add ENTREZ_KEY=...", "install BLAST+"),
    stringsAsFactors = FALSE
  )
  txt <- .format_check_block(chk)

  expect_match(txt, "1 ok, 1 warn, 1 missing.", fixed = TRUE)
  # The two non-ok rows appear, with their fixes.
  expect_match(txt, "key:ENTREZ_KEY", fixed = TRUE)
  expect_match(txt, "install BLAST+", fixed = TRUE)
  # The ok row does not: it is not something the model can act on, and an
  # edges-scoped check is mostly ok rows.
  expect_false(grepl("R version", txt, fixed = TRUE))
})

test_that(".format_check_block() says so when nothing needs attention", {
  chk <- data.frame(
    component = "R version", category = "r", status = "ok",
    detail = "4.5.2", fix = "", stringsAsFactors = FALSE
  )
  expect_match(.format_check_block(chk, all_ok_note = "All good."), "All good.", fixed = TRUE)
})

test_that("a real workflow_check() never renders a key VALUE into the prompt", {
  # Statuses only. If a key is set, its value must not reach the model.
  withr_key <- Sys.getenv("ENTREZ_KEY", unset = NA)
  Sys.setenv(ENTREZ_KEY = "SECRET-CANARY-VALUE-123")
  on.exit({
    if (is.na(withr_key)) Sys.unsetenv("ENTREZ_KEY") else Sys.setenv(ENTREZ_KEY = withr_key)
  }, add = TRUE)

  txt <- .format_check_block(workflow_check(verbose = FALSE))
  expect_false(grepl("SECRET-CANARY-VALUE-123", txt, fixed = TRUE))
})

test_that(".detect_paths_in_text() returns only paths that exist", {
  real <- tempfile(fileext = ".csv")
  writeLines("a,b\n1,2", real)
  on.exit(unlink(real), add = TRUE)

  msg <- sprintf('My data is at "%s" and maybe at "%s".', real, "/no/such/place/fake.csv")
  found <- .detect_paths_in_text(msg)

  expect_true(real %in% found)
  expect_false("/no/such/place/fake.csv" %in% found)
})

test_that(".detect_paths_in_text() finds nothing in prose with no path", {
  expect_equal(
    .detect_paths_in_text("I have some BirdNET results from three recorders."),
    character(0)
  )
})

test_that(".format_sniff_block() tells the model to ask when no path was found", {
  txt <- .format_sniff_block(character(0))
  expect_match(txt, "Ask the user for the path", fixed = TRUE)
})

test_that(".format_sniff_block() reports what sniff_input() found", {
  f <- tempfile(fileext = ".csv")
  writeLines(c(
    "Start (s),End (s),Scientific name,Common name,Confidence",
    "0.0,3.0,Catharus ustulatus,Swainson's Thrush,0.81"
  ), f)
  on.exit(unlink(f), add = TRUE)

  txt <- .format_sniff_block(f)
  expect_match(txt, "sniff_input() inspected", fixed = TRUE)
  expect_match(txt, f, fixed = TRUE)
  expect_match(txt, "node_id", fixed = TRUE)
})


# --- Paths containing spaces -------------------------------------------------
# Until 2026-09-20 .detect_paths_in_text() matched only whitespace-free tokens,
# so an unquoted path through a folder with a space in its name was never
# sniffed and {{SNIFF_RESULT}} degraded to "nothing was inspected" while the
# file sat right there. That is not an exotic case: Google Drive's own folder
# is "My Drive", and this project lives under it. Found by the P7(a) console
# dry run, which passed a real unquoted fixture path and was told it could not
# be found.

test_that(".detect_paths_in_text() finds an UNQUOTED path containing a space", {
  d <- file.path(tempdir(), "My Drive"); dir.create(d, showWarnings = FALSE)
  f <- file.path(d, "match obj.rds"); saveRDS(1, f)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  expect_true(f %in% .detect_paths_in_text(sprintf("my data is at %s ok", f)))
})

test_that(".detect_paths_in_text() strips trailing sentence punctuation", {
  d <- file.path(tempdir(), "My Drive"); dir.create(d, showWarnings = FALSE)
  f <- file.path(d, "match obj.rds"); saveRDS(1, f)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  expect_true(f %in% .detect_paths_in_text(sprintf("my data is at %s.", f)))
})

test_that(".detect_paths_in_text() still handles the cases it always did", {
  # The space rule is ADDITIVE -- quoted paths and whitespace-free paths must
  # keep working. A bare directory mention (no data-file extension) is no
  # longer auto-sniffed as of the confidentiality fix: auto-sniffing is now
  # gated on .SNIFF_DATA_EXTS, and a directory has no extension to check --
  # see .sniff_path_allowed()'s docstring.
  f <- file.path(tempdir(), "plain_data.csv"); writeLines("a,b", f)
  d <- file.path(tempdir(), "birdnet_out"); dir.create(d, showWarnings = FALSE)
  on.exit({ unlink(f); unlink(d, recursive = TRUE) }, add = TRUE)

  expect_true(f %in% .detect_paths_in_text(sprintf("data at %s ok", f)))
  expect_true(f %in% .detect_paths_in_text(sprintf('data at "%s" ok', f)))
  expect_equal(.detect_paths_in_text(sprintf("my CSVs are in %s/", d)), character(0))
})

test_that(".detect_paths_in_text() does not invent paths from prose", {
  # The other half of the proof. Being generous with CANDIDATES is only safe
  # because file.exists() adjudicates; a detector that reported a path the
  # user never gave would be worse than one that reported none.
  expect_equal(.detect_paths_in_text("I have BirdNET output from three recorders."), character(0))
  expect_equal(.detect_paths_in_text("data at /no/such/dir/My File.rds ok"), character(0))
  expect_equal(.detect_paths_in_text("the split was 3/4 of samples."), character(0))
})

test_that(".detect_paths_in_text() returns the whole path, not a suffix of it", {
  d <- file.path(tempdir(), "My Drive"); dir.create(d, showWarnings = FALSE)
  f <- file.path(d, "obj.rds"); saveRDS(1, f)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  found <- .detect_paths_in_text(sprintf("see %s now", f))
  expect_equal(found[1L], f)
})


# ==============================================================================
# Confidentiality gate on auto-sniffing (DEFECT-1 fix): a bare mention of an
# existing file's path must not have its content read and injected into an
# LLM prompt just because the message happened to contain that path.
# ==============================================================================

test_that(".detect_paths_in_text() does not auto-sniff a mentioned /etc/hosts", {
  # /etc/hosts is a universally-present, non-crafted file -- this is the
  # DEFECT-1 reproduction from the template review, run against the fix.
  msg <- "not sure what to run, my config is at /etc/hosts I think"
  expect_equal(.detect_paths_in_text(msg), character(0))

  block <- .format_sniff_block(.detect_paths_in_text(msg))
  expect_match(block, "nothing was inspected", fixed = TRUE)
})

test_that(".detect_paths_in_text() does not auto-sniff a mentioned dotfile, even with an allowed extension", {
  dir <- file.path(tempdir(), sprintf("taxawizard-dot-%s", basename(tempfile())))
  dir.create(dir, recursive = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  hidden <- file.path(dir, ".secret.csv")
  writeLines(c("token", "AKIAFAKEACCESSKEY1234"), hidden)

  # Quoted (an explicit act) AND inside the trusted tempdir() scratch space --
  # the dot-segment rule must still block it on both counts.
  msg <- sprintf('my config is at "%s" I think', hidden)
  expect_equal(.detect_paths_in_text(msg), character(0))

  block <- .format_sniff_block(.detect_paths_in_text(msg))
  expect_false(grepl("AKIAFAKE", block, fixed = TRUE))
})

test_that(".detect_paths_in_text() DOES auto-sniff a data file under the working directory, and the block never carries a cell value", {
  fname <- "tw_test_species_list.csv"
  full <- file.path(getwd(), fname)
  writeLines(c("species,family", "Eucyclogobius newberryi,Gobiidae"), full)
  on.exit(unlink(full), add = TRUE)

  msg <- sprintf("my species list is at %s please check it", full)
  found <- .detect_paths_in_text(msg)
  expect_true(full %in% found)

  block <- .format_sniff_block(found)
  expect_match(block, "species", fixed = TRUE) # column name surfaces
  expect_match(block, "family", fixed = TRUE)
  expect_false(grepl("newberryi", block, fixed = TRUE)) # never a cell VALUE
})

test_that("sniff_input() reports an oversized .rds by size only, never calling readRDS()", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "big.rds")
  # Padding to exceed the 1 MB cap without ever saveRDS()-ing a huge object.
  writeBin(raw(TaxaWizard:::.SNIFF_SIZE_CAP + 100000L), f)

  testthat::local_mocked_bindings(
    readRDS = function(...) stop("readRDS() must not be called for an oversized .rds file"),
    .package = "TaxaWizard"
  )

  out <- sniff_input(f)
  expect_true(is.na(out$node_id))
  expect_match(out$evidence, "MB", fixed = TRUE)
  expect_match(out$evidence, "not loaded", fixed = TRUE)
})

test_that("sniff_input() never echoes raw file content for an unclassifiable/single-column file", {
  dir <- .tw_sniff_dir()
  f <- file.path(dir, "creds.txt")
  writeLines("AKIAFAKEACCESSKEY1234 supersecretvalue==", f)

  out <- sniff_input(f)
  expect_false(grepl("AKIAFAKE", out$evidence, fixed = TRUE))
  expect_false(grepl("supersecretvalue", out$evidence, fixed = TRUE))
})

test_that("an absent Bioconductor package stops Step 0 only when the selected edges require it", {
  local_mocked_bindings(
    requireNamespace = function(package, ...) !(package %in% c("Biostrings", "DECIPHER")),
    .package = "base"
  )
  options(TaxaWizard.offline = TRUE)
  # an edge that never touches sequence alignment
  scoped <- workflow_check(edges = "match_to_consensus_score", verbose = FALSE)
  bio <- scoped[scoped$component %in% c("Biostrings", "DECIPHER"), ]
  expect_equal(nrow(bio), 2L)
  expect_true(all(bio$status == "warn"))
  expect_true(all(grepl("not needed by the selected steps", bio$detail, fixed = TRUE)))
  expect_false(any(scoped$status == "missing" & scoped$category == "package"))
  # an edge that aligns sequences still calls them missing
  needs <- workflow_check(edges = "refs_to_matrix", verbose = FALSE)
  expect_true(all(needs$status[needs$component %in% c("Biostrings", "DECIPHER")] == "missing"))
  # and so does the whole-ecosystem check
  whole <- workflow_check(verbose = FALSE)
  expect_true(all(whole$status[whole$component %in% c("Biostrings", "DECIPHER")] == "missing"))
})
