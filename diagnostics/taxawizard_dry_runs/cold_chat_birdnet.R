# P7(b): cold-chat dry run. A plain chat model gets ONLY the prompt pack text
# (START_HERE + CONTEXT_TaxaID + a setup report) and a scripted naive user.
.libPaths(c(path.expand("~/Library/R/4.0/library"), .libPaths()))
suppressMessages(library(TaxaWizard))
args <- commandArgs(trailingOnly = TRUE)
tier <- if (length(args)) args[1] else "fast"
root <- path.expand("~/My Drive/Rscripts/projects/TaxaID")
pack <- file.path(root, "llm_prompts")
rd <- function(f) paste(readLines(file.path(pack, f), warn = FALSE), collapse = "\n")

# A setup report for a user WITHOUT GBIF/NCBI keys (statuses only, values never shown)
setup_report <- "TaxaWizard setup check (user's machine)
component            status   fix
r_version            ok
TaxaTools..TaxaFlag  ok (8 packages)
pkg:Biostrings       ok
pkg:DECIPHER         ok
key:llm              ok       (ANTHROPIC_API_KEY set, found in ~/.Renviron)
key:ENTREZ_KEY       warn     usethis::edit_r_environ(); add ENTREZ_KEY=...; restart R
key:gbif             warn     GBIF_USER/GBIF_PWD/GBIF_EMAIL unset; only needed for the download API
key:INAT_API_TOKEN   warn     unset
bin:blastn           warn     not on PATH; use method = \"remote\"
net:*                skip     offline check
0 missing, 5 warn"

system_block <- paste0(
  "=== FILE: START_HERE.md ===\n", rd("START_HERE.md"),
  "\n\n=== FILE: CONTEXT_TaxaID.md ===\n", rd("CONTEXT_TaxaID.md"),
  "\n\n=== FILE: SETUP_REPORT.md (pasted by user) ===\n", setup_report,
  "\n\n=== FILE: tasks/handoff_template.md ===\n", rd("tasks/handoff_template.md"),
  "\n\n(You are the assistant. The files above are the only TaxaID knowledge you may use. ",
  "Continue the conversation below; reply as the assistant only, in prose.)\n\n")

user_turns <- c(
  "Hi. I have BirdNET output from three recorders in a Sierra Nevada meadow (CSV files in ~/birdnet_out/). I want a species list per recorder that has been checked for plausibility given the location. I'm using the Claude web chat, so I can't give you access to my files.",
  "Recorders at 38.90, -120.20, montane wet meadow, recorded June 2025, target group is birds. I ran the setup check; the report is the SETUP_REPORT.md I pasted. I want R code I can run myself. What's the plan?",
  paste0("sniff_input() says: node_id = birdnet_detections, confidence = high, evidence = 'BirdNET-Analyzer CSV header (Start (s), End (s), Scientific name, Common name, Confidence)'. ",
         "Here is CONTEXT_TaxaMatch.md as you asked:\n\n", rd("CONTEXT_TaxaMatch.md"),
         "\n\nNow please give me the script for the first stage."),
  "That ran fine. What is the plan for the remaining stages, as edge ids, and which CONTEXT file do you need next?"
)

transcript <- ""
out <- c()
for (i in seq_along(user_turns)) {
  transcript <- paste0(transcript, "USER: ", user_turns[i], "\n\nASSISTANT: ")
  reply <- TaxaTools::call_api(paste0(system_block, transcript), provider = "anthropic",
                               tier = tier, max_tokens = 6000L)
  transcript <- paste0(transcript, reply, "\n\n")
  out <- c(out, sprintf("---------------- TURN %d (user) ----------------\n%s\n\n---------------- TURN %d (assistant, tier=%s) ----------------\n%s\n",
                        i, user_turns[i], i, tier, reply))
}
writeLines(out, file.path(Sys.getenv("P7_OUT", tempdir()), paste0("p7b_transcript_", tier, ".md")))

# --- automatic checks -------------------------------------------------------
all_text <- paste(transcript, collapse = "\n")
# assistant-only text: drop the user turns (one of them pastes a whole CONTEXT file)
asst_text <- paste(vapply(strsplit(transcript, "ASSISTANT: ")[[1]][-1], function(r) sub("USER:.*$", "", r), ""), collapse = "\n")
reg <- workflow_registry()
exports <- unlist(lapply(reg, function(p) vapply(p$functions, `[[`, "", "name")))
called <- unique(regmatches(asst_text, gregexpr("Taxa[A-Za-z]+::[A-Za-z_]+", asst_text))[[1]])
called <- called[!grepl("^TaxaWizard::", called)]
called_fn <- sub(".*::", "", called)
bad <- called[!called_fn %in% exports]
graph <- jsonlite::fromJSON(system.file("graph", "workflow_graph.json", package = "TaxaWizard"), simplifyVector = FALSE)
edge_ids <- vapply(graph$edges, `[[`, "", "id")
edges_mentioned <- edge_ids[vapply(edge_ids, function(e) grepl(e, all_text, fixed = TRUE), TRUE)]
cat("\n=== AUTOMATIC CHECKS (tier=", tier, ") ===\n", sep = "")
cat("declares chat mode:      ", grepl("chat mode", all_text, ignore.case = TRUE), "\n")
cat("names input node:        ", grepl("birdnet_detections", all_text), "\n")
cat("names output node:       ", grepl("\\breviewed\\b", all_text), "\n")
cat("edges mentioned:         ", paste(edges_mentioned, collapse = ", "), "\n")
cat("mentions key:llm/API key:", grepl("key:llm|API key", all_text), "\n")
cat("asks for package CONTEXT:", grepl("CONTEXT_Taxa[A-Za-z]+\\.md", all_text), "\n")
cat("Pkg::fn calls used:      ", length(called), " ; NOT in registry: ", if (length(bad)) paste(bad, collapse = ", ") else "none", "\n")
# named-argument check on every Pkg::fn(...) call inside ```r blocks
code_blocks <- regmatches(asst_text, gregexpr("```r\\n.*?```", asst_text))[[1]]
code <- paste(gsub("```r\\n|```", "", code_blocks), collapse = "\n")
stale <- character()
if (nzchar(code)) {
  exprs <- tryCatch(parse(text = code, keep.source = FALSE), error = function(e) NULL)
  walk <- function(x) {
    if (is.call(x)) {
      f <- x[[1]]
      if (is.call(f) && identical(f[[1]], as.name("::")) && as.character(f[[2]]) %in% names(reg)) {
        pkg <- as.character(f[[2]]); fn <- as.character(f[[3]])
        entry <- Filter(function(e) e$name == fn, reg[[pkg]]$functions)
        if (length(entry)) {
          formals_ok <- vapply(entry[[1]]$params, `[[`, "", "name")
          given <- names(as.list(x))[-1]; given <- given[nzchar(given)]
          if (!"..." %in% formals_ok) stale <<- c(stale, paste0(pkg, "::", fn, "(", setdiff(given, formals_ok), ")")[length(setdiff(given, formals_ok)) > 0])
        }
      }
      for (a in as.list(x)[-1]) if (!identical(a, quote(expr = ))) walk(a)
    }
  }
  if (!is.null(exprs)) for (e in exprs) walk(e) else stale <- "PARSE ERROR in generated code"
}
cat("stale named args:        ", if (length(stale)) paste(stale, collapse = "; ") else "none", "\n")
cat("turn replies end with ?: ", paste(vapply(strsplit(transcript, "ASSISTANT: ")[[1]][-1], function(r) grepl("\\?\\s*$", trimws(sub("USER:.*$", "", r))), TRUE), collapse = " "), "\n")
cat("transcript saved to:", file.path(Sys.getenv("P7_OUT", tempdir()), paste0("p7b_transcript_", tier, ".md")), "\n")
