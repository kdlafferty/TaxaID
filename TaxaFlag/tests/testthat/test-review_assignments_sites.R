# Site-aware geography: review_assignments(sites =, site_col =). Every test uses
# a mock llm_fn. The sites = NULL path is pinned to literals recorded from the
# unmodified function (commit 8c2619c4) before this feature was written.

.gs_asked <- function(prompt) {
  part <- sub("(?s).*TAXA TO REVIEW:\n", "", prompt, perl = TRUE)
  lines <- grep("^- \\[T[0-9]+\\] ", strsplit(part, "\n", fixed = TRUE)[[1]], value = TRUE)
  list(
    id = sub("^- \\[(T[0-9]+)\\] .*$", "\\1", lines),
    label = sub("^- \\[T[0-9]+\\] ", "", lines)
  )
}

# geo: named list, taxon label -> raw JSON text of geographic_by_site
# (NULL entry or absent name = field omitted). base: geographic_plausibility.
.gs_fn <- function(geo = list(), base = "likely", log = NULL) {
  force(geo)
  force(base)
  function(prompt_str, ...) {
    if (!is.null(log)) log$n <- (log$n %||% 0L) + 1L
    a <- .gs_asked(prompt_str)
    objs <- vapply(seq_along(a$id), function(i) {
      g <- geo[[a$label[i]]]
      b <- if (length(base) > 1L) base[[a$label[i]]] else base
      sprintf(
        '{"id": "%s", "taxon_name": "%s", "habitat_plausibility": "likely", "geographic_plausibility": "%s", %s"scope_plausibility": "likely", "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "ok"}',
        a$id[i], a$label[i], b,
        if (is.null(g)) "" else sprintf('"geographic_by_site": %s, ', g)
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
.gs_by_site <- function(geo, base = "likely", ...) {
  out <- .gs_review(rep("Taxon a", 3L), .gs_fn(list(`Taxon a` = geo), base),
    site_vec = c("North", "Mid", "South"), ...
  )
  setNames(out$llm_geographic_plausibility_site, c("North", "Mid", "South"))
}

# --- 1. sites = NULL is byte-identical to the unmodified function ------------

test_that("sites = NULL: prompt, cache key, cache file and columns equal the frozen baseline", {
  df <- data.frame(
    obs = c("o1", "o2", "o3"),
    consensus_taxon = c("Gobiidae", "Sardinops sagax", "Gobiidae"),
    stringsAsFactors = FALSE
  )
  fn <- function(prompt_str, ...) {
    '[{"id":"T1","taxon_name":"Gobiidae","habitat_plausibility":"likely","geographic_plausibility":"likely","scope_plausibility":"likely","contamination_risk":"low","review_confidence":"high","review_comment":"ok"},{"id":"T2","taxon_name":"Sardinops sagax","habitat_plausibility":"likely","geographic_plausibility":"likely","scope_plausibility":"likely","contamination_risk":"low","review_confidence":"high","review_comment":"ok"}]'
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
    "v5\001fish\00112S\001eDNA\001FALSE\001frozen\001geography=Pacific coast|habitat=rocky intertidal\001Gobiidae\001NA\001FALSE\001FALSE",
    "v5\001fish\00112S\001eDNA\001FALSE\001frozen\001geography=Pacific coast|habitat=rocky intertidal\001Sardinops sagax\001NA\001FALSE\001FALSE"
  )
  expect_identical(keys, frozen)
  expect_identical(
    sort(basename(files)),
    c("0000448723-0000441094-000102_review.rds", "0000520483-0000509337-000109_review.rds")
  )
  fixture <- readLines(testthat::test_path("fixtures", "review_assignments_null_prompt.txt"),
    warn = FALSE
  )
  expect_identical(
    strsplit(attr(out, "llm_prompts")[["1"]], "\n", fixed = TRUE)[[1]], fixture
  )
  expect_identical(names(out), c(
    "obs", "consensus_taxon", "llm_habitat_plausibility",
    "llm_geographic_plausibility", "llm_scope_plausibility",
    "llm_contamination_risk", "review_alternatives", "review_lower_hypotheses",
    "review_confidence", "review_comment", "geographic_disagreement_basis"
  ))
  expect_null(attr(out, "geographic_by_site"))
  expect_false(any(grepl("STUDY SITES|geographic_by_site", attr(out, "llm_prompts")[["1"]])))
})

# --- 2. prompt with sites ------------------------------------------------------

test_that("the prompt lists sites south to north and asks for geographic_by_site", {
  out <- .gs_review("Taxon a", .gs_fn(list(`Taxon a` = '{"rule":"all"}')), site_vec = "North")
  p <- attr(out, "llm_prompts")[["1"]]
  expect_match(p, "STUDY SITES (name, latitude, longitude; sorted south to north):", fixed = TRUE)
  expect_true(regexpr("  South (32.00, -117.00)", p, fixed = TRUE) <
    regexpr("  Mid (34.40, -120.00)", p, fixed = TRUE))
  expect_true(regexpr("  Mid (34.40, -120.00)", p, fixed = TRUE) <
    regexpr("  North (38.00, -123.00)", p, fixed = TRUE))
  expect_match(p, '"geographic_by_site": where in the STUDY SITES', fixed = TRUE)
  expect_match(p, '"geographic_by_site": {"rule": "all"}', fixed = TRUE)
  expect_match(p, "\"inside\" is the verdict for a site within the range", fixed = TRUE)
  expect_match(p, "Judge GEOGRAPHY (range) only", fixed = TRUE)
})

# --- 3. the three rule shapes --------------------------------------------------

test_that("rule 'all' gives the study-wide verdict at every site", {
  v <- .gs_by_site('{"rule":"all"}', base = "possible")
  expect_equal(unname(v), rep("possible", 3L))
})

test_that("rule 'latitude' applies the outside verdict beyond the bounds", {
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":35,"outside":"unlikely"}')
  expect_equal(v[["South"]], "likely")
  expect_equal(v[["Mid"]], "likely")
  expect_equal(v[["North"]], "unlikely")
  v2 <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":33,"lat_max":40,"outside":"possible"}')
  expect_equal(v2[["South"]], "possible")
  expect_equal(v2[["Mid"]], "likely")
})

test_that("rule 'sites' marks the named sites unlikely; unknown names are ignored and counted", {
  v <- .gs_by_site('{"rule":"sites","inside":"likely","unlikely_sites":["North"," south ","Nowhere"]}')
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "unlikely"))
  out <- .gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = '{"rule":"sites","inside":"likely","unlikely_sites":["North","Nowhere"]}')),
    site_vec = c("North", "Mid", "South")
  )
  a <- attr(out, "geographic_by_site")
  expect_equal(a$rule, "sites")
  expect_equal(a$unlikely_sites, "North")
  expect_equal(a$n_unknown_sites, 1L)
})

# --- 4. latitude edge cases and fallbacks ---------------------------------------

test_that("one NA bound is open-ended; reversed bounds are swapped; missing outside is 'possible'", {
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":null,"lat_max":35,"outside":"unlikely"}')
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "likely"))
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":33,"lat_max":null,"outside":"unlikely"}')
  expect_equal(unname(v[c("North", "Mid", "South")]), c("likely", "likely", "unlikely"))
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":35,"lat_max":30,"outside":"unlikely"}')
  expect_equal(unname(v[c("North", "Mid", "South")]), c("unlikely", "likely", "likely"))
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":35}')
  expect_equal(unname(v[c("North", "Mid", "South")]), c("possible", "likely", "likely"))
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":35,"outside":"bogus"}')
  expect_equal(v[["North"]], "possible")
  v <- .gs_by_site('{"rule":"latitude","inside":"likely","lat_min":"31","lat_max":"36","outside":"unlikely"}')
  expect_equal(v[["North"]], "unlikely")
})

test_that("every fallback gives the study-wide verdict at every site and is recorded", {
  cases <- list(
    missing = NULL,
    not_object = '"all"',
    unknown_rule = '{"rule":"everywhere"}',
    all_sites_unknown = '{"rule":"sites","inside":"likely","unlikely_sites":["Atlantis","Mu"]}'
  )
  for (nm in names(cases)) {
    geo <- if (is.null(cases[[nm]])) list() else list(`Taxon a` = cases[[nm]])
    out <- .gs_review(rep("Taxon a", 3L), .gs_fn(geo, "possible"),
      site_vec = c("North", "Mid", "South")
    )
    expect_equal(out$llm_geographic_plausibility_site, rep("possible", 3L), info = nm)
    expect_equal(out$llm_geographic_plausibility, rep("possible", 3L), info = nm)
    a <- attr(out, "geographic_by_site")
    expect_equal(a$rule, "fallback", info = nm)
  }
  expect_equal(
    attr(.gs_review("Taxon a", .gs_fn(list(`Taxon a` = '{"rule":"sites","inside":"likely","unlikely_sites":["Atlantis"]}')),
      site_vec = "North"),
      "geographic_by_site")$how,
    "all_sites_unknown"
  )
})

test_that("inside is respected with no cap from geographic_plausibility; study-wide is the best over sites", {
  # model says 'unlikely' (habitat/rarity) but the band says inside = possible:
  # the inside sites are 'possible' (old behaviour capped them at 'unlikely')
  g <- '{"rule":"latitude","lat_min":30,"lat_max":35,"inside":"possible","outside":"unlikely"}'
  out <- .gs_review(rep("Taxon a", 3L), .gs_fn(list(`Taxon a` = g), base = "unlikely"),
    site_vec = c("North", "Mid", "South")
  )
  expect_equal(out$llm_geographic_plausibility_site, c("unlikely", "possible", "possible"))
  expect_equal(out$llm_geographic_plausibility, rep("possible", 3L))
  # sites rule with inside
  out <- .gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = '{"rule":"sites","unlikely_sites":["North"],"inside":"likely"}'), base = "unlikely"),
    site_vec = c("North", "Mid", "South")
  )
  expect_equal(out$llm_geographic_plausibility_site, c("unlikely", "likely", "likely"))
  expect_equal(out$llm_geographic_plausibility, rep("likely", 3L))
  # missing inside -> possible, never base (here base = likely)
  v <- .gs_by_site('{"rule":"latitude","lat_min":30,"lat_max":35,"outside":"unlikely"}', base = "likely")
  expect_equal(unname(v), c("unlikely", "possible", "possible"))
  v <- .gs_by_site('{"rule":"sites","unlikely_sites":["North"]}', base = "likely")
  expect_equal(unname(v), c("unlikely", "possible", "possible"))
  # invalid inside (including 'unlikely') -> possible
  v <- .gs_by_site('{"rule":"latitude","lat_min":30,"lat_max":35,"inside":"bogus","outside":"unlikely"}')
  expect_equal(unname(v), c("unlikely", "possible", "possible"))
  v <- .gs_by_site('{"rule":"sites","unlikely_sites":["North"],"inside":"unlikely"}')
  expect_equal(unname(v), c("unlikely", "possible", "possible"))
  # rule 'all' unchanged: the model's geographic_plausibility everywhere
  v <- .gs_by_site('{"rule":"all"}', base = "unlikely")
  expect_equal(unname(v), rep("unlikely", 3L))
  # every site outside the range and outside = unlikely: best over sites is unlikely
  out <- .gs_review(rep("Taxon a", 3L),
    .gs_fn(list(`Taxon a` = '{"rule":"latitude","lat_min":10,"lat_max":20,"inside":"likely","outside":"unlikely"}')),
    site_vec = c("North", "Mid", "South")
  )
  expect_equal(out$llm_geographic_plausibility, rep("unlikely", 3L))
  expect_equal(out$llm_geographic_plausibility_site, rep("unlikely", 3L))
  # the attr carries inside
  expect_true("inside" %in% names(attr(out, "geographic_by_site")))
  expect_equal(attr(out, "geographic_by_site")$inside, "likely")
})

test_that("a fallback spec gives every site the study-wide verdict; best-over-sites is idempotent", {
  for (b in c("unlikely", "likely", "possible")) {
    for (g in c('{"rule":"bogus"}', '{"rule":"sites","unlikely_sites":["Atlantis"]}', '"text"')) {
      out <- .gs_review(rep("Taxon a", 3L), .gs_fn(list(`Taxon a` = g), base = b),
        site_vec = c("North", "Mid", "South")
      )
      expect_equal(out$llm_geographic_plausibility_site, rep(b, 3L))
      expect_equal(out$llm_geographic_plausibility, rep(b, 3L))
    }
  }
  expect_match(.geo_field_text, "MUST give at least one numeric bound", fixed = TRUE)
})

# --- 5. per-row join, unknown rows, output shape ---------------------------------

test_that("rows with NA or unknown site get the study-wide verdict; output shape", {
  geo <- list(
    `Taxon a` = '{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":33,"outside":"unlikely"}',
    `Taxon b` = '{"rule":"all"}'
  )
  df <- data.frame(
    tx = c("Taxon a", "Taxon a", "Taxon a", "Taxon b"),
    site = c("North", NA, "Elsewhere", "North"), stringsAsFactors = FALSE
  )
  expect_warning(
    out <- review_assignments(df,
      taxon_col = "tx", context = .gs_ctx, data_type = "eDNA",
      llm_fn = .gs_fn(geo), model_label = "frozen", pause_seconds = 0,
      verbose = FALSE, sites = .gs_sites
    ),
    "Elsewhere"
  )
  # study-wide for Taxon a = best over sites = likely (South in range)
  expect_equal(out$llm_geographic_plausibility_site, c("unlikely", "likely", "likely", "likely"))
  expect_equal(
    match("llm_geographic_plausibility_site", names(out)),
    match("llm_geographic_plausibility", names(out)) + 1L
  )
  a <- attr(out, "geographic_by_site")
  expect_equal(sort(a$taxon), c("Taxon a", "Taxon b"))
  expect_equal(a$rule[a$taxon == "Taxon a"], "latitude")
  expect_equal(a$lat_min[a$taxon == "Taxon a"], 30)
  expect_equal(a$outside[a$taxon == "Taxon a"], "unlikely")
  expect_equal(nrow(out), 4L)
})

test_that("an unreviewed taxon stays NA in the site column", {
  fn <- function(prompt_str, ...) "[]"
  out <- suppressWarnings(.gs_review("Taxon a", fn, site_vec = "North", max_retries = 0L, on_unreviewed = "ignore"))
  expect_true(is.na(out$llm_geographic_plausibility_site))
  expect_equal(nrow(attr(out, "geographic_by_site")), 0L)
})

# --- 6. validation ---------------------------------------------------------------

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
  # extra columns are ignored
  out <- run(sites = transform(.gs_sites, elev = 1))
  expect_true("llm_geographic_plausibility_site" %in% names(out))
})

# --- 7. cache -----------------------------------------------------------------------

test_that("cache: sites and no-sites never serve each other; a hit reproduces the site column", {
  cd <- tempfile("gs_cache")
  geo <- list(`Taxon a` = '{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":33,"outside":"unlikely"}')
  log <- new.env()
  fn <- .gs_fn(geo, log = log)
  sv <- c("North", "Mid", "South")
  r1 <- .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd)
  expect_equal(log$n, 1L)
  # same call: hit, no LLM call, same per-site column
  r2 <- .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd)
  expect_equal(log$n, 1L)
  expect_equal(r2$llm_geographic_plausibility_site, c("unlikely", "unlikely", "likely"))
  expect_identical(attr(r2, "geographic_by_site"), attr(r1, "geographic_by_site"))
  # a different site_col does not matter to the key; a reordered table is a hit
  r3 <- .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd, sites = .gs_sites[3:1, ])
  expect_equal(log$n, 1L)
  expect_equal(r3$llm_geographic_plausibility_site, r2$llm_geographic_plausibility_site)
  # a moved site is a miss
  moved <- .gs_sites
  moved$lat[1] <- 36
  .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd, sites = moved)
  expect_equal(log$n, 2L)
  # no sites: miss (the sites entry is not served) ...
  df <- data.frame(tx = "Taxon a", stringsAsFactors = FALSE)
  nosite <- function() {
    review_assignments(df,
      taxon_col = "tx", context = .gs_ctx, data_type = "eDNA", llm_fn = fn,
      model_label = "frozen", pause_seconds = 0, verbose = FALSE, cache_dir = cd
    )
  }
  r4 <- nosite()
  expect_equal(log$n, 3L)
  expect_false("llm_geographic_plausibility_site" %in% names(r4))
  # ... and the no-sites entry is not served to a sites call, nor the reverse
  nosite()
  expect_equal(log$n, 3L)
  .gs_review(rep("Taxon a", 3L), fn, site_vec = sv, cache_dir = cd)
  expect_equal(log$n, 3L)
  keys <- vapply(list.files(cd, full.names = TRUE), function(f) readRDS(f)$key, character(1))
  expect_equal(sum(grepl("geo_sites_v4", keys, fixed = TRUE)), 2L)
  expect_equal(sum(!grepl("geo_sites_v4", keys, fixed = TRUE)), 1L)
  expect_false(any(grepl("geo_sites_v3", keys, fixed = TRUE)))
  # an entry keyed on an older sites wording is a miss, not a stale hit
  v4 <- keys[grepl("geo_sites_v4", keys, fixed = TRUE)][1L]
  expect_false(identical(v4, sub("geo_sites_v4", "geo_sites_v3", v4, fixed = TRUE)))
})

# --- 8. truncated JSON with the nested object ---------------------------------------------

test_that(".recover_truncated_json keeps complete objects that contain geographic_by_site", {
  full <- paste0(
    '[{"id":"T1","taxon_name":"A","geographic_plausibility":"likely","geographic_by_site":{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":null,"outside":"unlikely"},"review_comment":"x"},',
    '{"id":"T2","taxon_name":"B","geographic_plausibility":"possible","geographic_by_site":{"rule":"sites","inside":"likely","unlikely_sites":["North","South"]},"review_comment":"y"},',
    '{"id":"T3","taxon_name":"C","geographic_plausibility":"likely","geographic_by_site":{"rule":"lat'
  )
  rec <- TaxaFlag:::.recover_truncated_json(full)
  expect_true(is.data.frame(rec))
  expect_equal(nrow(rec), 2L)
  expect_equal(rec$taxon_name, c("A", "B"))
  g1 <- TaxaFlag:::.normalise_geo_obj(TaxaFlag:::.geo_obj_at(rec$geographic_by_site, 1L), .gs_sites$site)
  g2 <- TaxaFlag:::.normalise_geo_obj(TaxaFlag:::.geo_obj_at(rec$geographic_by_site, 2L), .gs_sites$site)
  expect_equal(g1$rule, "latitude")
  expect_equal(g1$lat_min, 30)
  expect_true(is.na(g1$lat_max))
  expect_equal(g2$unlikely_sites, c("North", "South"))
  # cut inside the nested object of the last complete-looking taxon
  cut2 <- sub('"review_comment":"y"\\}.*$', '"review_comment":"y"}', full)
  expect_equal(nrow(TaxaFlag:::.recover_truncated_json(cut2)), 2L)
})

test_that("a truncated response with nested objects is halved and retried to completion", {
  n <- 0L
  full <- .gs_fn(list(
    `Taxon a` = '{"rule":"latitude","inside":"likely","lat_min":30,"lat_max":33,"outside":"unlikely"}',
    `Taxon b` = '{"rule":"sites","inside":"likely","unlikely_sites":["North"]}'
  ))
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    txt <- full(prompt_str)
    if (n == 1L) substr(txt, 1L, nchar(txt) - 120L) else txt
  }
  out <- .gs_review(c("Taxon a", "Taxon b"), fn, site_vec = c("North", "North"), max_retries = 2L)
  expect_equal(out$llm_geographic_plausibility_site, c("unlikely", "unlikely"))
  expect_false(anyNA(out$llm_habitat_plausibility))
  expect_equal(nrow(attr(out, "geographic_by_site")), 2L)
})

test_that("the parser tolerates geographic_by_site as a string, a list or mixed shapes", {
  txt <- paste0(
    '[{"id":"T1","taxon_name":"A","geographic_plausibility":"likely","geographic_by_site":"all"},',
    '{"id":"T2","taxon_name":"B","geographic_plausibility":"likely","geographic_by_site":{"rule":"all"}},',
    '{"id":"T3","taxon_name":"C","geographic_plausibility":"likely","geographic_by_site":null},',
    '{"id":"T4","taxon_name":"D","geographic_plausibility":"likely"}]'
  )
  tb <- data.frame(taxon_name = c("A", "B", "C", "D"), taxon_rank = NA_character_, stringsAsFactors = FALSE)
  res <- TaxaFlag:::.parse_review_response(txt, tb, NULL, NULL, site_names = .gs_sites$site)
  rules <- vapply(res$review_geo_json, function(j) TaxaFlag:::.geo_spec_from_json(j)$rule, "")
  expect_equal(unname(rules), c("fallback", "all", "fallback", "fallback"))
})

test_that("a both-bounds-NA latitude rule is read as 'all' carrying inside (the study-wide verdict if missing/invalid)", {
  nb <- c("North", "Mid", "South")
  cases <- list(
    likely = '{"rule":"latitude","inside":"likely","lat_min":null,"lat_max":null,"outside":"unlikely"}',
    possible = '{"rule":"latitude","inside":"possible","lat_min":null,"lat_max":null}',
    missing = '{"rule":"latitude","lat_min":null,"lat_max":null}',
    invalid = '{"rule":"latitude","inside":"unlikely","lat_min":"29N","lat_max":"far"}'
  )
  for (nm in names(cases)) {
    for (b in c("unlikely", "possible", "likely")) {
      want <- c(likely = "likely", possible = "possible", missing = b, invalid = b)
      out <- .gs_review(rep("Taxon a", 3L), .gs_fn(list(`Taxon a` = cases[[nm]]), base = b), site_vec = nb)
      expect_equal(out$llm_geographic_plausibility_site, rep(want[[nm]], 3L), info = nm)
      expect_equal(out$llm_geographic_plausibility, rep(want[[nm]], 3L), info = nm)
      expect_equal(attr(out, "geographic_by_site")$how, "both_bounds_NA_as_all", info = nm)
    }
  }
  # plain 'all' is unchanged: the model's own verdict, how = "all"
  out <- .gs_review(rep("Taxon a", 3L), .gs_fn(list(`Taxon a` = '{"rule":"all","inside":"likely"}'), base = "unlikely"), site_vec = nb)
  expect_equal(out$llm_geographic_plausibility_site, rep("unlikely", 3L))
  expect_equal(attr(out, "geographic_by_site")$how, "all")
})
