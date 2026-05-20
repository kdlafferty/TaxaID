# test-report_section.R
# Tests for new_report_section(), print/format methods, and assemble_report()

test_that("new_report_section creates valid object", {
  sec <- new_report_section(
    package = "TestPkg", section = "test",
    methods = "Methods text here.",
    results = "Results text here.",
    citations = c("Cite A", "Cite B"),
    params = list(method = "BLAST"),
    statistics = list(n = 100L)
  )

  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TestPkg")
  expect_equal(sec$section, "test")
  expect_equal(sec$methods, "Methods text here.")
  expect_equal(sec$results, "Results text here.")
  expect_equal(sec$citations, c("Cite A", "Cite B"))
  expect_equal(sec$params$method, "BLAST")
  expect_equal(sec$statistics$n, 100L)
})

test_that("new_report_section works with NULL optional fields", {
  sec <- new_report_section(
    package = "Pkg", section = "s",
    methods = "M."
  )

  expect_s3_class(sec, "report_section")
  expect_null(sec$results)
  expect_null(sec$citations)
  expect_null(sec$params)
  expect_null(sec$statistics)
})

test_that("new_report_section validates inputs", {
  expect_error(new_report_section(package = "", section = "s", methods = "M"))
  expect_error(new_report_section(package = "P", section = "", methods = "M"))
  expect_error(new_report_section(package = "P", section = "s", methods = c("a", "b")))
  expect_error(new_report_section(package = "P", section = "s", methods = "M",
                                  results = c("a", "b")))
  expect_error(new_report_section(package = "P", section = "s", methods = "M",
                                  citations = 123))
  expect_error(new_report_section(package = "P", section = "s", methods = "M",
                                  params = "not a list"))
  expect_error(new_report_section(package = "P", section = "s", methods = "M",
                                  statistics = "not a list"))
})

test_that("print.report_section outputs markdown", {

  sec <- new_report_section(
    package = "TaxaFetch", section = "fetch",
    methods = "Data from GBIF.",
    results = "1000 records.",
    citations = c("GBIF.org")
  )

  output <- capture.output(print(sec))
  expect_true(any(grepl("## Methods", output)))
  expect_true(any(grepl("## Results", output)))
  expect_true(any(grepl("## Data Sources", output)))
  expect_true(any(grepl("GBIF.org", output)))
})

test_that("format.report_section returns markdown string", {
  sec <- new_report_section(
    package = "Pkg", section = "s",
    methods = "Methods.",
    results = "Results."
  )

  txt <- format(sec)
  expect_type(txt, "character")
  expect_true(grepl("## Methods", txt))
  expect_true(grepl("## Results", txt))
})

test_that("assemble_report orders sections by pipeline position", {
  assign_sec <- new_report_section(package = "A", section = "assign", methods = "Assign.")
  fetch_sec  <- new_report_section(package = "F", section = "fetch", methods = "Fetch.")
  match_sec  <- new_report_section(package = "M", section = "match", methods = "Match.")

  # Pass in wrong order — should reorder
  report <- assemble_report(assign_sec, fetch_sec, match_sec)

  # fetch should appear before match, match before assign
  fetch_pos  <- regexpr("Fetch\\.", report)

  match_pos  <- regexpr("Match\\.", report)
  assign_pos <- regexpr("Assign\\.", report)

  expect_true(fetch_pos < match_pos)
  expect_true(match_pos < assign_pos)
})

test_that("assemble_report deduplicates citations", {
  sec1 <- new_report_section(package = "A", section = "fetch", methods = "M.",
                             citations = c("Cite A", "Cite B"))
  sec2 <- new_report_section(package = "B", section = "match", methods = "M.",
                             citations = c("Cite B", "Cite C"))

  report <- assemble_report(sec1, sec2)

  # Each citation should appear exactly once
  expect_equal(length(gregexpr("Cite A", report)[[1]]), 1)
  expect_equal(length(gregexpr("Cite B", report)[[1]]), 1)
  expect_equal(length(gregexpr("Cite C", report)[[1]]), 1)
})

test_that("assemble_report accepts a list of sections", {
  secs <- list(
    new_report_section(package = "A", section = "fetch", methods = "Fetch."),
    new_report_section(package = "B", section = "match", methods = "Match.")
  )

  report <- assemble_report(secs)
  expect_true(grepl("Fetch\\.", report))
  expect_true(grepl("Match\\.", report))
})

test_that("assemble_report includes title and study_description", {
  sec <- new_report_section(package = "A", section = "fetch", methods = "M.")

  report <- assemble_report(sec, title = "My Report",
                            study_description = "This study examined fish.")
  expect_true(grepl("# My Report", report))
  expect_true(grepl("This study examined fish", report))
})

test_that("assemble_report errors on non-section objects", {
  expect_error(assemble_report(data.frame(x = 1)))
  expect_error(assemble_report())
})

test_that("assemble_report separates Methods from Results", {
  sec <- new_report_section(package = "A", section = "fetch",
                            methods = "METHODS_TEXT",
                            results = "RESULTS_TEXT")
  report <- assemble_report(sec)

  methods_pos <- regexpr("METHODS_TEXT", report)
  results_pos <- regexpr("RESULTS_TEXT", report)
  expect_true(methods_pos < results_pos)

  # Both should be under their own ## heading
  expect_true(grepl("## Methods.*METHODS_TEXT", report))
  expect_true(grepl("## Results.*RESULTS_TEXT", report))
})
