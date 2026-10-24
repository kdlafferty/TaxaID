# Site-aware geography: review_assignments(sites =, site_col =).
# Every test uses a mock llm_fn.
#
# The model states its range LIMITS and TaxaFlag computes the site and study
# probabilities from them, so these tests exercise the limits, the named-site
# escape hatch and the cuts -- not a per-site verdict the model chose.

.gs_asked <- function(prompt) {
  part <- sub("(?s).*TAXA TO REVIEW:\n", "", prompt, perl = TRUE)
  lines <- grep("^- \\[T[0-9]+\\] ", strsplit(part, "\n", fixed = TRUE)[[1]], value = TRUE)
  list(
    id = sub("^- \\[(T[0-9]+)\\] .*$", "\\1", lines),
    label = sub("^- \\[T[0-9]+\\] (.*?)( \\[.*)?$", "\\1", lines),
    line = lines
  )
}

# One geography answer, as the raw JSON fragment the model would return.
.gs_geo <- function(south = "null", north = "null", outside = character(0),
                    p_in = "0.9", p_out = "0.05", known = "true", extra = "") {
  paste0(
    sprintf(
      '"range_known": %s, "range_south_lat": %s, "range_north_lat": %s, "sites_outside_range": [%s]',
      known, south, north, paste(sprintf('"%s"', outside), collapse = ",")
    ),
    if (identical(p_in, "")) "" else sprintf(', "p_inside_range": %s', p_in),
    if (identical(p_out, "")) "" else sprintf(', "p_outside_range": %s', p_out),
    extra
  )
}

# ans: named list, taxon label -> geography JSON fragment (default: whole study
# in range). p_hab: scalar or a named list per label.
.gs_fn <- function(ans = list(), p_hab = "0.95", log = NULL) {
  force(ans)
  force(p_hab)
  function(prompt_str, ...) {
    if (!is.null(log)) log$n <- (log$n %||% 0L) + 1L
    a <- .gs_asked(prompt_str)
    objs <- vapply(seq_along(a$id), function(i) {
      g <- ans[[a$label[i]]]
      if (is.null(g)) g <- .gs_geo()
      h <- if (length(p_hab) > 1L) p_hab[[a$label[i]]] else p_hab
      sprintf(
        paste0(
          '{"id": "%s", "taxon_name": "%s", "p_habitat": %s, ',
          '"p_habitat_range": [0.90, 0.99], "p_transported": 0.50, ',
          '"p_scope": 0.95, "p_scope_range": [0.90, 0.99], %s, ',
          '"p_contamination": 0.02, "review_alternatives": null, ',
          '"review_lower_hypotheses": null, "review_confidence": "high", ',
          '"review_comment": "ok"}'
        ),
        a$id[i], a$label[i], h, g
      )
    }, character(1))
    paste0("[", paste(objs, collapse = ","), "]")
  }
}

.gs_sites <- data.frame(
  site = c("North", "South", "Mid"), lat = c(38, 32, 34.4),
  lon = c(-123, -117, -120), stringsAsFactors = FALSE
)

.gs_ctx <- list(geography = "Pacific coast", habitat = "rocky intertidal")

.gs_review <- function(taxa, llm_fn, site_vec = NULL, ..., sites = .gs_sites) {
  df <- data.frame(obs = paste0("o", seq_along(taxa)), tx = taxa, stringsAsFactors = FALSE)
  if (!is.null(site_vec)) df$site <- site_vec
  review_assignments(df,
    taxon_col = "tx", context = .gs_ctx, data_type = "eDNA",
    llm_fn = llm_fn, model_label = "frozen", pause_seconds = 0,
    verbose = FALSE, sites = sites, ...
  )
}

# One taxon, one row per site: the per-site verdicts in North/Mid/South order.
.gs_by_site <- function(geo, ..., what = "llm_geographic_plausibility_site") {
  out <- .gs_review(rep("Taxon a", 3L), .gs_fn(list(`Taxon a` = geo)),
    site_vec = c("North", "Mid", "South"), ...
  )
  setNames(out[[what]], c("North", "Mid", "South"))
}

# --- 1. sites = NULL: the prompt, key, file name and columns are pinned --------
# Not "unchanged from before the feature" -- the answer format changed for every
# path at v7 -- but pinned, so an unintended change to any of them fails here.

test_that("sites = NULL: prompt, cache key, cache file and columns are pinned", {
  df <- data.frame(
    obs = c("o1", "o2", "o3"),
    consensus_taxon = c("Gobiidae", "Sardinops sagax", "Gobiidae"),
    stringsAsFactors = FALSE
  )
  fn <- function(prompt_str, ...) {
    paste0(
      '[{"id":"T1","taxon_name":"Gobiidae","p_habitat":0.95,"p_geographic":0.95,',
      '"p_scope":0.95,"p_contamination":0.02,"review_confidence":"high",',
      '"review_comment":"ok"},{"id":"T2","taxon_name":"Sardinops sagax",',
      '"p_habitat":0.95,"p_geographic":0.95,"p_scope":0.95,',
      '"p_contamination":0.02,"review_confidence":"high","review_comment":"ok"}]'
    )
  }
  cd <- tempfile("gs_cache")
  out <- review_assignments(df,
    context = list(geography = "Pacific coast", habitat = "rocky intertidal"),
    target_group = "fish", marker = "12S", data_type = "eDNA", llm_fn = fn,
    model_label = "frozen", cache_dir = cd, pause_seconds = 0, verbose = FALSE
  )
  files <- list.files(cd, full.names = TRUE)
  keys <- sort(vapply(files, function(f) readRDS(f)$key, character(1), USE.NAMES = FALSE))
  frozen <- c(
    "v11\001fish\00112S\001eDNA\001FALSE\001frozen\001geography=Pacific coast|habitat=rocky intertidal\001Gobiidae\001NA\001FALSE\001FALSE",
    "v11\001fish\00112S\001eDNA\001FALSE\001frozen\001geography=Pacific coast|habitat=rocky intertidal\001Sardinops sagax\001NA\001FALSE\001FALSE"
  )
  expect_identical(keys, frozen)
  fixture <- readLines(
    testthat::test_path("fixtures", "review_assignments_null_prompt.txt"),
    warn = FALSE
  )
  expect_identical(
    strsplit(attr(out, "llm_prompts")[["1"]], "\n", fixed = TRUE)[[1]], fixture
  )
  expect_identical(names(out), c(
    "obs", "consensus_taxon", "llm_habitat_plausibility",
    "llm_geographic_plausibility", "llm_scope_plausibility",
    "llm_contamination_risk", "review_alternatives", "review_lower_hypotheses",
    "review_confidence", "review_comment",
    "llm_p_habitat", "llm_p_habitat_lo", "llm_p_habitat_hi",
    "llm_p_transported", "llm_p_scope", "llm_p_scope_lo", "llm_p_scope_hi",
    "llm_p_contamination", "llm_p_geographic", "geographic_disagreement_basis"
  ))
  expect_null(attr(out, "geographic_by_site"))
  # No site table: no site block, no range fields, no detected-at bracket.
  p <- attr(out, "llm_prompts")[["1"]]
  expect_false(any(grepl("STUDY SITES|range_south_lat|detected at", p)))
  expect_match(p, '"p_geographic": probability that the study area lies within',
    fixed = TRUE
  )
})

# --- 2. the prompt with sites --------------------------------------------------

test_that("the prompt lists sites south to north and asks for range limits", {
  out <- .gs_review("Taxon a", .gs_fn(), site_vec = "North")
  p <- attr(out, "llm_prompts")[["1"]]
  expect_match(p, "STUDY SITES (name, latitude, longitude; sorted south to north):",
    fixed = TRUE
  )
  expect_true(regexpr("  South (32.00, -117.00)", p, fixed = TRUE) <
    regexpr("  Mid (34.40, -120.00)", p, fixed = TRUE))
  expect_true(regexpr("  Mid (34.40, -120.00)", p, fixed = TRUE) <
    regexpr("  North (38.00, -123.00)", p, fixed = TRUE))
  expect_match(p, '"range_south_lat": the southern limit', fixed = TRUE)
  expect_match(p, '"range_north_lat": the northern limit', fixed = TRUE)
  expect_match(p, '"sites_outside_range"', fixed = TRUE)
  expect_match(p, "Decide which side each limit is on before answering", fixed = TRUE)
  expect_match(p, "site verdicts are computed from your limits", fixed = TRUE)
  # the taxon's own detected sites, north to south, and the bracket's guideline
  expect_match(p, "[detected at: North (38.0 N)]", fixed = TRUE)
  expect_match(p, '- A "[detected at: ...]" bracket lists the sites', fixed = TRUE)
  # no site table means no study-wide geography field on this path
  expect_false(grepl('"p_geographic":', p, fixed = TRUE))
  # habitat and scope are asked as living conditions and kind of organism only
  expect_match(p, "whether it occurs in the study region is geography", fixed = TRUE)
  expect_match(p, "wherever its range is", fixed = TRUE)
})

test_that("the habitat and target-group strings come from the caller, not the code", {
  out <- review_assignments(
    data.frame(tx = "Taxon a", site = "North", stringsAsFactors = FALSE),
    taxon_col = "tx",
    context = list(geography = "Lake Superior", habitat = "Freshwater rocky littoral"),
    target_group = "freshwater fishes", data_type = "eDNA", llm_fn = .gs_fn(),
    model_label = "frozen", pause_seconds = 0, verbose = FALSE, sites = .gs_sites
  )
  p <- attr(out, "llm_prompts")[["1"]]
  expect_match(p, "study habitat (Freshwater rocky littoral)", fixed = TRUE)
  expect_match(p, "target group (freshwater fishes)", fixed = TRUE)
  expect_false(grepl("rocky intertidal|lanternfish|Point Conception", p))
  # the worked examples name no real taxon
  expect_match(p, "WORKED EXAMPLES (invented taxa)", fixed = TRUE)
})

# --- 3. the range limits become site probabilities -----------------------------

test_that("a southern limit puts the sites below it outside the range", {
  v <- .gs_by_site(.gs_geo(south = "33"))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("likely", "likely", "unlikely"))
  p <- .gs_by_site(.gs_geo(south = "33"), what = "llm_p_geographic_site")
  expect_equal(unname(p[c("North", "Mid", "South")]), c(0.9, 0.9, 0.05))
})

test_that("a northern limit puts the sites above it outside the range", {
  v <- .gs_by_site(.gs_geo(north = "35"))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "likely"))
})

test_that("both limits bound a band; no limit leaves every site inside", {
  v <- .gs_by_site(.gs_geo(south = "33", north = "35"))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "unlikely"))
  v <- .gs_by_site(.gs_geo())
  expect_equal(unname(v), rep("likely", 3L))
  expect_equal(
    attr(.gs_review("Taxon a", .gs_fn(), site_vec = "North"),
      "geographic_by_site"
    )$how,
    "no_limit_in_study"
  )
})

test_that("an inverted band is swapped, not obeyed, and the swap is recorded", {
  # a southern limit of 35 with a northern limit of 30 would put every site
  # outside and mark the taxon unlikely everywhere
  v <- .gs_by_site(.gs_geo(south = "35", north = "30"))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "likely"))
  a <- attr(.gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = .gs_geo(south = "35", north = "30"))),
    site_vec = c("North", "Mid", "South")
  ), "geographic_by_site")
  expect_equal(a$how, "range_swapped")
  expect_equal(a$range_south_lat, 30)
  expect_equal(a$range_north_lat, 35)
})

test_that("a latitude that is not a latitude is dropped", {
  v <- .gs_by_site(.gs_geo(south = '"29N"', north = '"far"'))
  expect_equal(unname(v), rep("likely", 3L))
  v <- .gs_by_site(.gs_geo(south = "200"))
  expect_equal(unname(v), rep("likely", 3L))
  # a numeric limit given as a string is still a number
  v <- .gs_by_site(.gs_geo(south = '"33"'))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("likely", "likely", "unlikely"))
})

test_that("the outside probability is the model's, and its absence never invents one", {
  v <- .gs_by_site(.gs_geo(south = "33", p_out = "0.4"))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("likely", "likely", "possible"))
  # no outside probability at all: the inside probability everywhere, so no
  # site is moved on the strength of a number the model never gave
  v <- .gs_by_site(.gs_geo(south = "33", p_out = ""))
  expect_equal(unname(v), rep("likely", 3L))
  v <- .gs_by_site(.gs_geo(south = "33", p_out = "1.4"))
  expect_equal(unname(v), rep("likely", 3L))
})

test_that("named sites are matched case- and space-insensitively and counted", {
  v <- .gs_by_site(.gs_geo(outside = c("North", " south ", "Nowhere")))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "unlikely"))
  a <- attr(.gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = .gs_geo(outside = c("North", "Nowhere")))),
    site_vec = c("North", "Mid", "South")
  ), "geographic_by_site")
  expect_equal(a$sites_outside_range, "North")
  expect_equal(a$n_unknown_sites, 1L)
  expect_equal(a$how, "sites_unknown_ignored")
})

test_that("a list in which no name is recognised is dropped whole", {
  v <- .gs_by_site(.gs_geo(outside = c("Atlantis", "Mu")))
  expect_equal(unname(v), rep("likely", 3L))
  a <- attr(.gs_review("Taxon a", .gs_fn(
    list(`Taxon a` = .gs_geo(outside = c("Atlantis", "Mu")))
  ), site_vec = "North"), "geographic_by_site")
  expect_equal(a$sites_outside_range, "")
  expect_equal(a$n_unknown_sites, 2L)
})

test_that("range_known = FALSE gives every site the inside probability", {
  v <- .gs_by_site(.gs_geo(south = "33", known = "false", p_in = "0.5"))
  expect_equal(unname(v), rep("possible", 3L))
  a <- attr(.gs_review("Taxon a", .gs_fn(list(
    `Taxon a` = .gs_geo(south = "33", known = "false", p_in = "0.5")
  )), site_vec = "North"), "geographic_by_site")
  expect_equal(a$rule, "unknown")
  expect_match(a$how, "range_unknown")
  # ... but a site it named explicitly is still honoured: "I don't know the
  # limits" and "not at that site" are different claims
  v <- .gs_by_site(.gs_geo(
    known = "false", p_in = "0.5", p_out = "0.02", outside = "North"
  ))
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "possible", "possible"))
})

test_that("no usable inside probability yields no geography, and is re-asked", {
  # the spec itself: no probability in, no probability out, never a guess
  for (bad in list(NULL, NA, "high", 1.5, -0.2)) {
    spec <- TaxaFlag:::.normalise_range_answer(
      list(range_known = TRUE, range_south_lat = 33, p_inside_range = bad),
      .gs_sites$site
    )
    expect_equal(spec$rule, "fallback")
    expect_equal(spec$how, "no_inside_probability")
    expect_true(all(is.na(TaxaFlag:::.geo_site_probs(spec, .gs_sites))))
  }
  # and through the function, such a row is an omission: geography drives a
  # decision, so it is re-asked rather than left as an NA the export filters
  # would discard
  out <- suppressWarnings(.gs_review("Taxon a",
    .gs_fn(list(`Taxon a` = .gs_geo(p_in = "null"))),
    site_vec = "North", max_retries = 0L, on_unreviewed = "ignore"
  ))
  expect_equal(attr(out, "unreviewed_taxa"), "Taxon a")
  expect_equal(nrow(attr(out, "geographic_by_site")), 0L)
})

test_that("a volunteered study-wide probability rescues a missing p_inside_range", {
  v <- .gs_by_site(.gs_geo(p_in = "null", extra = ', "p_geographic": 0.8'))
  expect_equal(unname(v), rep("likely", 3L))
})

# --- 4. the cuts ---------------------------------------------------------------

test_that("the margin cuts are the ones applied", {
  lv <- function(p) {
    unname(.gs_by_site(.gs_geo(p_in = format(p, nsmall = 2)))[["Mid"]])
  }
  expect_equal(lv(0.09), "unlikely")
  expect_equal(lv(0.10), "possible") # the boundary belongs to "possible"
  expect_equal(lv(0.69), "possible")
  expect_equal(lv(0.70), "likely") # and this one to "likely"
  expect_equal(TaxaFlag:::.p_to_level(c(0, 0.0999, 0.1, 0.6999, 0.7, 1, NA)), c(
    "unlikely", "unlikely", "possible", "possible", "likely", "likely", NA
  ))
  expect_equal(TaxaFlag:::.p_to_risk(c(0, 0.1999, 0.2, 0.6999, 0.7, 1, NA)), c(
    "low", "low", "moderate", "moderate", "high", "high", NA
  ))
})

test_that("a cut change re-reads a CACHED answer with no new call", {
  cd <- tempfile("gs_cut")
  log <- new.env()
  fn <- .gs_fn(list(`Taxon a` = .gs_geo(p_in = "0.5")), log = log)
  r1 <- .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
  expect_equal(log$n, 1L)
  expect_equal(r1$llm_geographic_plausibility, "possible")
  # 0.5 reads as "likely" once the likely cut drops below it -- from the cache
  old <- TaxaFlag:::.p_cut_likely
  ns <- asNamespace("TaxaFlag")
  unlockBinding(".p_cut_likely", ns)
  on.exit({
    assign(".p_cut_likely", old, envir = ns)
    lockBinding(".p_cut_likely", ns)
  }, add = TRUE)
  assign(".p_cut_likely", 0.4, envir = ns)
  r2 <- .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
  expect_equal(log$n, 1L) # no second call
  expect_equal(r2$llm_geographic_plausibility, "likely")
  expect_equal(r2$llm_p_geographic, 0.5) # the stored answer is untouched
})

# --- 5. the study-wide verdict is the best over the detected sites -------------

test_that("the study-wide pair is the maximum over sites, never the model's summary", {
  out <- .gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = .gs_geo(south = "33"))),
    site_vec = c("North", "Mid", "South")
  )
  expect_equal(out$llm_geographic_plausibility, rep("likely", 3L))
  expect_equal(out$llm_p_geographic, rep(0.9, 3L))
  # every site outside: the study-wide pair follows the sites down
  out <- .gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = .gs_geo(south = "40"))),
    site_vec = c("North", "Mid", "South")
  )
  expect_equal(out$llm_geographic_plausibility, rep("unlikely", 3L))
  expect_equal(out$llm_p_geographic, rep(0.05, 3L))
  # the study-wide verdict is the level of the maximum, which is also the best
  # site verdict: the cuts are monotone
  out <- .gs_review(rep("Taxon a", 2L),
    .gs_fn(list(`Taxon a` = .gs_geo(south = "33", p_out = "0.4"))),
    site_vec = c("South", "Mid")
  )
  expect_equal(out$llm_geographic_plausibility_site, c("possible", "likely"))
  expect_equal(out$llm_geographic_plausibility, rep("likely", 2L))
})

test_that("the study-wide maximum is over the DETECTED sites, not the whole table", {
  # the shape that exposed this on live data: one detected site, beyond the
  # stated limit, while another site in the table lies inside the range
  out <- .gs_review("Taxon a",
    .gs_fn(list(`Taxon a` = .gs_geo(north = "33", p_in = "0.5", p_out = "0.04"))),
    site_vec = "North"
  )
  expect_equal(out$llm_p_geographic_site, 0.04)
  expect_equal(out$llm_p_geographic, 0.04) # not 0.5 from South, where it was not detected
  expect_equal(out$llm_geographic_plausibility, "unlikely")
  # it matters because the geography override acts only when the study verdict
  # is likely or possible: 0.5 here would enable an override on evidence about
  # a site this taxon was never detected at
  expect_false(out$llm_geographic_plausibility %in% c("likely", "possible"))
  # detected at the in-range site as well: now the maximum is 0.5
  out2 <- .gs_review(rep("Taxon a", 2L),
    .gs_fn(list(`Taxon a` = .gs_geo(north = "33", p_in = "0.5", p_out = "0.04"))),
    site_vec = c("North", "South")
  )
  expect_equal(out2$llm_p_geographic, rep(0.5, 2L))
  expect_equal(out2$llm_geographic_plausibility, rep("possible", 2L))
})

test_that("the study probability never exceeds the maximum over the detected sites", {
  for (geo in list(
    .gs_geo(south = "33"), .gs_geo(north = "35"),
    .gs_geo(south = "33", north = "35"), .gs_geo(),
    .gs_geo(outside = "North"), .gs_geo(known = "false", p_in = "0.5"),
    .gs_geo(south = "40", p_out = "0.01")
  )) {
    for (sv in list("North", c("North", "Mid"), c("North", "Mid", "South"), "South")) {
      out <- .gs_review(rep("Taxon a", length(sv)),
        .gs_fn(list(`Taxon a` = geo)),
        site_vec = sv
      )
      expect_equal(out$llm_p_geographic, rep(max(out$llm_p_geographic_site), length(sv)))
      expect_true(all(out$llm_p_geographic <= max(out$llm_p_geographic_site)))
    }
  }
})

test_that("two taxa with identical answers but different detected sites differ", {
  geo <- .gs_geo(north = "33", p_in = "0.5", p_out = "0.04")
  out <- .gs_review(c("Taxon a", "Taxon b"),
    .gs_fn(list(`Taxon a` = geo, `Taxon b` = geo)),
    site_vec = c("North", "South")
  )
  # same range answer; a was detected outside it, b inside
  expect_equal(out$llm_p_geographic, c(0.04, 0.5))
  expect_equal(out$llm_geographic_plausibility, c("unlikely", "possible"))
})

test_that("a taxon whose every site is unknown falls back to the whole table", {
  expect_warning(
    out <- review_assignments(
      data.frame(tx = "Taxon a", site = "Elsewhere", stringsAsFactors = FALSE),
      taxon_col = "tx", context = .gs_ctx, data_type = "eDNA",
      llm_fn = .gs_fn(list(`Taxon a` = .gs_geo(north = "33", p_in = "0.5", p_out = "0.04"))),
      model_label = "frozen", pause_seconds = 0, verbose = FALSE, sites = .gs_sites
    ),
    "Elsewhere"
  )
  # no detected site to take a maximum over, so the table is all there is
  expect_equal(out$llm_p_geographic, 0.5)
})

# --- 6. per-row join, unknown rows, output shape ------------------------------

test_that("rows with NA or unknown site get the study-wide pair; output shape", {
  ans <- list(
    `Taxon a` = .gs_geo(south = "33", north = "35"),
    `Taxon b` = .gs_geo()
  )
  df <- data.frame(
    tx = c("Taxon a", "Taxon a", "Taxon a", "Taxon b"),
    site = c("North", NA, "Elsewhere", "North"), stringsAsFactors = FALSE
  )
  expect_warning(
    out <- review_assignments(df,
      taxon_col = "tx", context = .gs_ctx, data_type = "eDNA",
      llm_fn = .gs_fn(ans), model_label = "frozen", pause_seconds = 0,
      verbose = FALSE, sites = .gs_sites
    ),
    "Elsewhere"
  )
  # Taxon a: North is above 35, so unlikely. North is also its ONLY known
  # detected site, so the study-wide verdict is unlikely too, and the NA and
  # unknown rows take it. Mid lies inside the range but the taxon was never
  # detected there, so it cannot rescue the study verdict.
  # row 4 is Taxon b, whose answer states no limit at all
  expect_equal(out$llm_geographic_plausibility_site, c("unlikely", "unlikely", "unlikely", "likely"))
  expect_equal(out$llm_geographic_plausibility[1:3], rep("unlikely", 3L))
  expect_equal(
    match("llm_geographic_plausibility_site", names(out)),
    match("llm_geographic_plausibility", names(out)) + 1L
  )
  a <- attr(out, "geographic_by_site")
  expect_equal(sort(a$taxon), c("Taxon a", "Taxon b"))
  expect_equal(a$rule[a$taxon == "Taxon a"], "range")
  expect_equal(a$range_south_lat[a$taxon == "Taxon a"], 33)
  expect_equal(a$p_outside_range[a$taxon == "Taxon a"], 0.05)
  expect_equal(nrow(out), 4L)
  expect_true(all(c(
    "llm_p_geographic_site", "llm_p_inside_range", "llm_p_outside_range",
    "llm_range_known", "llm_range_south_lat", "llm_range_north_lat"
  ) %in% names(out)))
})

test_that("an unreviewed taxon stays NA in the site column", {
  fn <- function(prompt_str, ...) "[]"
  out <- suppressWarnings(.gs_review("Taxon a", fn,
    site_vec = "North", max_retries = 0L, on_unreviewed = "ignore"
  ))
  expect_true(is.na(out$llm_geographic_plausibility_site))
  expect_true(is.na(out$llm_p_geographic_site))
  expect_equal(nrow(attr(out, "geographic_by_site")), 0L)
})

# --- 7. validation -----------------------------------------------------------

test_that("the sites table and site_col are validated", {
  fn <- .gs_fn()
  df <- data.frame(tx = "Taxon a", site = "North", stringsAsFactors = FALSE)
  run <- function(...) {
    review_assignments(df,
      taxon_col = "tx", context = .gs_ctx, data_type = "eDNA", llm_fn = fn,
      pause_seconds = 0, verbose = FALSE, ...
    )
  }
  expect_error(run(sites = "x"), "data frame")
  expect_error(run(sites = .gs_sites[, c("site", "lat")]), "missing column")
  expect_error(run(sites = transform(.gs_sites, lat = as.character(lat))), "numeric")
  expect_error(run(sites = transform(.gs_sites, lat = c(95, 32, 34))), "latitude outside")
  expect_error(run(sites = transform(.gs_sites, lon = c(-200, -117, -120))), "longitude outside")
  expect_error(run(sites = transform(.gs_sites, lat = c(NA, 32, 34))), "NA")
  expect_error(run(sites = transform(.gs_sites, site = c("A", "A", "B"))), "unique")
  expect_error(run(sites = transform(.gs_sites, site = c("A", NA, "B"))), "NA or empty")
  expect_error(run(sites = .gs_sites[0, ]), "no rows")
  expect_error(run(sites = .gs_sites, site_col = "nope"), "not found in input_df")
  out <- run(sites = transform(.gs_sites, elev = 1))
  expect_true("llm_geographic_plausibility_site" %in% names(out))
})

# --- 8. cache ----------------------------------------------------------------

test_that("cache: sites and no-sites never serve each other; a hit reproduces the site column", {
  cd <- tempfile("gs_cache")
  ans <- list(`Taxon a` = .gs_geo(south = "33", north = "35"))
  log <- new.env()
  fn <- .gs_fn(ans, log = log)
  sv <- c("North", "Mid", "South")
  r1 <- .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd)
  expect_equal(log$n, 1L)
  r2 <- .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd)
  expect_equal(log$n, 1L)
  expect_equal(r2$llm_geographic_plausibility_site, c("unlikely", "likely", "unlikely"))
  expect_identical(attr(r2, "geographic_by_site"), attr(r1, "geographic_by_site"))
  # a reordered sites table is the same question
  r3 <- .gs_review(rep("Taxon a", 3L), fn,
    site_vec = sv, cache_dir = cd,
    sites = .gs_sites[3:1, ]
  )
  expect_equal(log$n, 1L)
  expect_equal(r3$llm_geographic_plausibility_site, r2$llm_geographic_plausibility_site)
  # a moved site is a different question
  moved <- .gs_sites
  moved$lat[1] <- 36
  .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd, sites = moved)
  expect_equal(log$n, 2L)
  # a different set of detected sites is a different question, because the
  # taxon line itself changes
  .gs_review(rep("Taxon a", 2L), fn, site_vec = c("North", "Mid"), cache_dir = cd)
  expect_equal(log$n, 3L)
  df <- data.frame(tx = "Taxon a", stringsAsFactors = FALSE)
  # the no-sites schema asks for p_geographic, not range limits
  fn_ns <- function(prompt_str, ...) {
    log$n <- (log$n %||% 0L) + 1L
    a <- .gs_asked(prompt_str)
    paste0(
      '[{"id": "', a$id[1], '", "taxon_name": "', a$label[1], '", ',
      '"p_habitat": 0.95, "p_scope": 0.95, "p_contamination": 0.02, ',
      '"p_geographic": 0.95, "review_confidence": "high", ',
      '"review_comment": "ok"}]'
    )
  }
  nosite <- function() {
    review_assignments(df,
      taxon_col = "tx", context = .gs_ctx, data_type = "eDNA", llm_fn = fn_ns,
      model_label = "frozen", pause_seconds = 0, verbose = FALSE, cache_dir = cd
    )
  }
  r4 <- nosite()
  expect_equal(log$n, 4L)
  expect_false("llm_geographic_plausibility_site" %in% names(r4))
  nosite()
  expect_equal(log$n, 4L)
  keys <- vapply(list.files(cd, full.names = TRUE), function(f) readRDS(f)$key, character(1))
  expect_equal(sum(!grepl("geo_sites_v5", keys, fixed = TRUE)), 1L)
  expect_false(any(grepl("geo_sites_v4", keys, fixed = TRUE)))
})

test_that("two models behind the same wrapper source get different cache keys", {
  # the hole this closes: deparse(llm_fn) shows "model = MODEL", the variable
  # NAME, so a sonnet run and an opus run written with one wrapper would share
  # a key and the second would be served the first's answers
  mk <- function(model) {
    force(model)
    function(prompt_str, ...) .gs_fn()(prompt_str)
  }
  expect_false(identical(
    TaxaFlag:::.review_reviewer_id(mk("a-model"), model_label = "a-model"),
    TaxaFlag:::.review_reviewer_id(mk("b-model"), model_label = "b-model")
  ))
  # and with no model_label the wrapper is refused outright when caching,
  # rather than keyed on its source
  expect_error(
    TaxaFlag:::.review_reviewer_id(mk("a-model"), caching = TRUE),
    "cannot be identified"
  )
  expect_error(
    .gs_review("Taxon a", mk("a-model"),
      site_vec = "North",
      cache_dir = tempfile("gs_nolabel"), model_label = NULL
    ),
    "model_label"
  )
  # uncached, it is still keyed as before: no error
  expect_silent(id <- TaxaFlag:::.review_reviewer_id(mk("a-model")))
  expect_type(id, "character")
})

# --- 9. truncation with arrays in the answer ---------------------------------

test_that("a truncated response is halved and retried to completion", {
  n <- 0L
  full <- .gs_fn(list(
    `Taxon a` = .gs_geo(south = "33", north = "35"),
    `Taxon b` = .gs_geo(outside = "North")
  ))
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    txt <- full(prompt_str)
    if (n == 1L) substr(txt, 1L, nchar(txt) - 120L) else txt
  }
  out <- .gs_review(c("Taxon a", "Taxon b"), fn,
    site_vec = c("North", "North"), max_retries = 2L
  )
  expect_equal(out$llm_geographic_plausibility_site, c("unlikely", "unlikely"))
  expect_false(anyNA(out$llm_habitat_plausibility))
  expect_equal(nrow(attr(out, "geographic_by_site")), 2L)
})

test_that(".recover_truncated_json keeps complete objects carrying arrays", {
  full <- paste0(
    '[{"id":"T1","taxon_name":"A","p_habitat":0.95,"p_habitat_range":[0.9,0.99],',
    '"sites_outside_range":["North"],"p_inside_range":0.9,"p_outside_range":0.05},',
    '{"id":"T2","taxon_name":"B","p_habitat":0.4,"p_habitat_range":[0.2,0.6],',
    '"sites_outside_range":[],"p_inside_range":0.5,"p_outside_range":0.1},',
    '{"id":"T3","taxon_name":"C","p_habitat":0.9,"p_habitat_range":[0.8'
  )
  rec <- TaxaFlag:::.recover_truncated_json(full)
  expect_true(is.data.frame(rec))
  expect_equal(nrow(rec), 2L)
  expect_equal(rec$taxon_name, c("A", "B"))
})

test_that("the parser reads the range fields in whatever shape they arrive", {
  ok <- '"p_habitat":0.9,"p_contamination":0.02,'
  txt <- paste0(
    '[{"id":"T1","taxon_name":"A",', ok, '"p_inside_range":0.9,"p_outside_range":0.05,',
    '"range_known":true,"range_south_lat":33,"sites_outside_range":["North"]},',
    '{"id":"T2","taxon_name":"B",', ok, '"p_inside_range":0.9,"range_known":"true",',
    '"range_south_lat":null,"sites_outside_range":[]},',
    '{"id":"T3","taxon_name":"C",', ok, '"p_inside_range":0.9,"range_known":false},',
    '{"id":"T4","taxon_name":"D"}]'
  )
  tb <- data.frame(
    taxon_name = c("A", "B", "C", "D"), taxon_rank = NA_character_,
    stringsAsFactors = FALSE
  )
  res <- TaxaFlag:::.parse_review_response(txt, tb, NULL, NULL,
    site_names = .gs_sites$site
  )
  # D carried no probability at all, so it is an omission and is NA-filled,
  # not a parsed range answer
  expect_equal(attr(res, "missing_taxa"), "D")
  keep <- res$taxon_name %in% c("A", "B", "C")
  rules <- vapply(res$review_geo_json[keep], function(j) {
    TaxaFlag:::.geo_spec_from_json(j)$rule
  }, "")
  expect_equal(unname(rules), c("range", "range", "unknown"))
  expect_equal(res$range_south_lat[keep], c(33, NA, NA))
  expect_equal(res$range_known[keep], c(TRUE, TRUE, FALSE))
  expect_true(is.na(res$review_geo_json[res$taxon_name == "D"]))
})

# --- 10. deterministic batch order -------------------------------------------

test_that("the batches are built from a sort of the labels, not the input order", {
  seen <- new.env()
  fn <- function(prompt_str, ...) {
    a <- .gs_asked(prompt_str)
    seen$order <- c(seen$order, a$label)
    .gs_fn()(prompt_str)
  }
  taxa <- c("Zebra one", "Alpha two", "Mid three", "Beta four")
  .gs_review(taxa, fn, site_vec = rep("North", 4L), taxa_per_call = 2L)
  first <- seen$order
  seen$order <- NULL
  .gs_review(rev(taxa), fn, site_vec = rep("North", 4L), taxa_per_call = 2L)
  expect_equal(seen$order, first)
  expect_equal(first, sort(taxa))
})

# --- 11. the detected-sites bracket -----------------------------------------

test_that("the bracket lists the detected sites north to south, unknowns out", {
  expect_equal(
    TaxaFlag:::.detected_sites_bracket(c("South", "North"), .gs_sites),
    "[detected at: North (38.0 N); South (32.0 N)]"
  )
  # A site the table does not know has no latitude to place it by, so it is
  # left out here and takes the study-wide verdict downstream.
  expect_equal(
    TaxaFlag:::.detected_sites_bracket(c("North", "Nowhere"), .gs_sites),
    "[detected at: North (38.0 N)]"
  )
  expect_true(is.na(TaxaFlag:::.detected_sites_bracket("Nowhere", .gs_sites)))
  expect_true(is.na(TaxaFlag:::.detected_sites_bracket(character(0), .gs_sites)))
})

# --- 12. an unusable probability is an omission, not an answer ---------------

test_that("a probability that is not a probability is re-asked, never cached", {
  # p = 85 (a percentage) and p = "high" (a category) both leave every derived
  # verdict NA while review_confidence and review_comment arrive intact. That
  # row used to look reviewed: it was cached, n_unreviewed_rows said 0, and the
  # NA was dropped by every "!= unlikely" export filter without a word.
  for (bad in c("85", '"high"', "-0.2")) {
    junk <- function(prompt_str, ...) {
      a <- .gs_asked(prompt_str)
      paste0(
        '[{"id": "', a$id[1], '", "taxon_name": "', a$label[1], '", ',
        '"p_habitat": ', bad, ', "p_scope": ', bad, ', "p_contamination": ', bad,
        ', "range_known": true, "range_south_lat": null, ',
        '"range_north_lat": null, "sites_outside_range": [], ',
        '"p_inside_range": ', bad, ', "p_outside_range": ', bad, ', ',
        '"review_confidence": "high", "review_comment": "looks fine"}]'
      )
    }
    cd <- tempfile("gs_junk")
    out <- suppressWarnings(.gs_review("Taxon a", junk,
      site_vec = "North", max_retries = 0L, on_unreviewed = "ignore",
      cache_dir = cd
    ))
    expect_equal(attr(out, "unreviewed_taxa"), "Taxon a", info = bad)
    expect_equal(attr(out, "n_unreviewed_rows"), 1L, info = bad)
    expect_true(is.na(out$llm_habitat_plausibility), info = bad)
    # and nothing was written, so the next run asks again
    expect_equal(
      length(list.files(cd, pattern = "_review\\.rds$")), 0L,
      info = bad
    )
  }
})

test_that("ANY unusable decision-driving probability is re-asked, not kept", {
  # three questions answered and the fourth fumbled still leaves one NA that
  # the "!= unlikely" export filters discard silently, so the row is re-asked
  partial <- function(prompt_str, ...) {
    a <- .gs_asked(prompt_str)
    paste0(
      '[{"id": "', a$id[1], '", "taxon_name": "', a$label[1], '", ',
      '"p_habitat": 0.9, "p_scope": 0.9, "p_contamination": "high", ',
      '"range_known": true, "range_south_lat": null, "range_north_lat": null, ',
      '"sites_outside_range": [], "p_inside_range": 0.9, ',
      '"p_outside_range": 0.05, "review_confidence": "high", ',
      '"review_comment": null}]'
    )
  }
  cd <- tempfile("gs_partial")
  out <- suppressWarnings(.gs_review("Taxon a", partial,
    site_vec = "North", max_retries = 0L, on_unreviewed = "ignore",
    cache_dir = cd
  ))
  expect_equal(attr(out, "unreviewed_taxa"), "Taxon a")
  expect_equal(attr(out, "n_unreviewed_rows"), 1L)
  expect_equal(length(list.files(cd, pattern = "_review\\.rds$")), 0L)
  # the warning names the count and the field, so a non-verbose run sees it
  expect_warning(
    .gs_review("Taxon a", partial,
      site_vec = "North", max_retries = 0L, on_unreviewed = "ignore"
    ),
    "unusable probability.*p_contamination",
    all = FALSE
  )
})

test_that("p_habitat alone, and p_inside_range alone, each trigger a re-ask", {
  one_bad <- function(field, value) {
    function(prompt_str, ...) {
      a <- .gs_asked(prompt_str)
      f <- list(p_habitat = "0.9", p_scope = "0.9", p_contamination = "0.02",
                p_inside_range = "0.9")
      f[[field]] <- value
      paste0(
        '[{"id": "', a$id[1], '", "taxon_name": "', a$label[1], '", ',
        '"p_habitat": ', f$p_habitat, ', "p_scope": ', f$p_scope, ', ',
        '"p_contamination": ', f$p_contamination, ', "range_known": true, ',
        '"range_south_lat": null, "range_north_lat": null, ',
        '"sites_outside_range": [], "p_inside_range": ', f$p_inside_range,
        ', "p_outside_range": 0.05, "review_confidence": "high", ',
        '"review_comment": null}]'
      )
    }
  }
  for (case in list(c("p_habitat", '"high"'), c("p_inside_range", "85"),
                    c("p_contamination", '"low"'))) {
    out <- suppressWarnings(.gs_review("Taxon a", one_bad(case[1], case[2]),
      site_vec = "North", max_retries = 0L, on_unreviewed = "ignore"
    ))
    expect_equal(attr(out, "unreviewed_taxa"), "Taxon a", info = case[1])
  }
  # p_scope is asked ONLY when target_group is set, so a bad one is not a
  # non-answer without it -- the scope question was never put
  out <- .gs_review("Taxon a", one_bad("p_scope", "-1"), site_vec = "North")
  expect_equal(attr(out, "unreviewed_taxa"), character(0))
  expect_true(is.na(out$llm_scope_plausibility))
  out <- suppressWarnings(.gs_review("Taxon a", one_bad("p_scope", "-1"),
    site_vec = "North", target_group = "fish", max_retries = 0L,
    on_unreviewed = "ignore"
  ))
  expect_equal(attr(out, "unreviewed_taxa"), "Taxon a")
  # p_outside_range is NOT decision-driving: its absence gives the inside
  # probability everywhere, which is the stated conservative reading
  no_out <- function(prompt_str, ...) {
    a <- .gs_asked(prompt_str)
    paste0(
      '[{"id": "', a$id[1], '", "taxon_name": "', a$label[1], '", ',
      '"p_habitat": 0.9, "p_scope": 0.9, "p_contamination": 0.02, ',
      '"range_known": true, "range_south_lat": 33, "range_north_lat": null, ',
      '"sites_outside_range": [], "p_inside_range": 0.9, ',
      '"review_confidence": "high", "review_comment": null}]'
    )
  }
  out <- .gs_review("Taxon a", no_out, site_vec = "North")
  expect_equal(attr(out, "unreviewed_taxa"), character(0))
  expect_equal(out$llm_geographic_plausibility_site, "likely")
})

test_that("a row that still fails every re-ask is counted, never dropped quietly", {
  n <- 0L
  always_bad <- function(prompt_str, ...) {
    n <<- n + 1L
    a <- .gs_asked(prompt_str)
    paste0(
      '[{"id": "', a$id[1], '", "taxon_name": "', a$label[1], '", ',
      '"p_habitat": "high", "p_scope": 0.9, "p_contamination": 0.02, ',
      '"range_known": true, "range_south_lat": null, ',
      '"range_north_lat": null, "sites_outside_range": [], ',
      '"p_inside_range": 0.9, "p_outside_range": 0.05, ',
      '"review_confidence": "high", "review_comment": null}]'
    )
  }
  cd <- tempfile("gs_persist")
  expect_warning(
    out <- .gs_review("Taxon a", always_bad,
      site_vec = "North", max_retries = 2L, cache_dir = cd
    ),
    "NO LLM verdict"
  )
  expect_gt(n, 1L) # it was re-asked
  expect_equal(attr(out, "unreviewed_taxa"), "Taxon a")
  expect_equal(attr(out, "n_unreviewed_rows"), 1L)
  expect_true(is.na(out$llm_habitat_plausibility))
  expect_equal(length(list.files(cd, pattern = "_review\\.rds$")), 0L)
})

test_that("a PARTIALLY unusable cached entry is a miss, on the same asked set", {
  # the read side has to apply the same test as the write side. If writing
  # refuses a row with ONE unusable probability while reading only rejects a
  # row with NONE usable, an entry from any earlier build is served as a hit
  # forever and its NA is dropped by every export filter.
  blank_one <- function(cd, col) {
    for (fl in list.files(cd, pattern = "_review\\.rds$", full.names = TRUE)) {
      e <- readRDS(fl)
      e$row[[col]] <- NA_real_
      saveRDS(e, fl)
    }
  }
  for (col in c("p_habitat", "p_contamination", "p_geographic")) {
    cd <- tempfile("gs_part")
    log <- new.env()
    fn <- .gs_fn(log = log)
    .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
    expect_equal(log$n, 1L, info = col)
    blank_one(cd, col)
    .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
    expect_equal(log$n, 2L, info = col) # a miss, re-asked
  }
  # p_scope counts only when a target group was asked about
  cd <- tempfile("gs_scope_ng")
  log <- new.env()
  fn <- .gs_fn(log = log)
  .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
  blank_one(cd, "p_scope")
  .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
  expect_equal(log$n, 1L) # no target_group: NA p_scope is the right value, a HIT
  cd2 <- tempfile("gs_scope_tg")
  log2 <- new.env()
  fn2 <- .gs_fn(log = log2)
  .gs_review("Taxon a", fn2,
    site_vec = "North", cache_dir = cd2, target_group = "fish"
  )
  expect_equal(log2$n, 1L)
  blank_one(cd2, "p_scope")
  .gs_review("Taxon a", fn2,
    site_vec = "North", cache_dir = cd2, target_group = "fish"
  )
  expect_equal(log2$n, 2L) # with a target group it is a miss
})

test_that("a cached non-answer from before this fix is a miss, not a hit", {
  cd <- tempfile("gs_stale")
  log <- new.env()
  fn <- .gs_fn(log = log)
  .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
  expect_equal(log$n, 1L)
  # blank every probability in the cached entry, leaving the confidence and
  # comment a pre-fix entry would have carried
  files <- list.files(cd, pattern = "_review\\.rds$", full.names = TRUE)
  expect_gt(length(files), 0L)
  for (fl in files) {
    e <- readRDS(fl)
    for (cl in grep("^p_", names(e$row), value = TRUE)) e$row[[cl]] <- NA_real_
    for (cl in c("habitat_plausibility", "scope_plausibility",
                 "contamination_risk", "geographic_plausibility")) {
      if (cl %in% names(e$row)) e$row[[cl]] <- NA_character_
    }
    saveRDS(e, fl)
  }
  .gs_review("Taxon a", fn, site_vec = "North", cache_dir = cd)
  expect_equal(log$n, 2L)
})

test_that("the cuts used are stamped on the result", {
  out <- .gs_review("Taxon a", .gs_fn(), site_vec = "North")
  cuts <- attr(out, "review_cuts")
  expect_equal(cuts[["unlikely_below"]], 0.10)
  expect_equal(cuts[["likely_at"]], 0.70)
  expect_equal(cuts[["contamination_moderate_at"]], 0.20)
  expect_equal(cuts[["contamination_high_at"]], 0.70)
})
