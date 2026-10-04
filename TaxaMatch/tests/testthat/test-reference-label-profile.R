# Tests for the rank profile, the all-deposit search helpers and marker
# resolution (R/reference_label_profile.R). Fully offline.

# Two families x two genera x two species, each species in 3 batches.
.mk_profile_pool <- function() {
  sp <- c("Aus alpha", "Aus beta", "Bus gamma", "Bus delta")
  gen <- c("Aus", "Aus", "Bus", "Bus")
  fam <- c("Fa", "Fa", "Fa", "Fa")
  dep <- do.call(rbind, lapply(seq_along(sp), function(i) {
    data.frame(acc = sprintf("%s%d", c("AA", "BB", "CC")[1:3], 100 * i + 1:3) ,
               species = sp[i], genus = gen[i], family = fam[i], class = "Cx",
               stringsAsFactors = FALSE)
  }))
  # three separate batches per species (accession prefixes differ)
  dep$acc <- c("AA101", "BB101", "CC101", "AA201", "BB201", "CC201",
               "AA301", "BB301", "CC301", "AA401", "BB401", "CC401")
  dep$batch <- dep$acc
  dep
}
.mk_profile_hits <- function(dep) {
  # identity: same species 99, same genus 95, same family 90
  pairs <- expand.grid(q = dep$acc, s = dep$acc, stringsAsFactors = FALSE)
  pairs <- pairs[pairs$q != pairs$s, ]
  sq <- dep$species[match(pairs$q, dep$acc)]; ss <- dep$species[match(pairs$s, dep$acc)]
  gq <- dep$genus[match(pairs$q, dep$acc)]; gs <- dep$genus[match(pairs$s, dep$acc)]
  pairs$pid <- ifelse(sq == ss, 99, ifelse(gq == gs, 95, 90))
  pairs
}

test_that(".mislabel_bare_acc() strips legacy BLAST id wrappers and versions", {
  expect_identical(.mislabel_bare_acc(c("dbj|AB033668|", "gb|MT1.2|", "AB1.1", "emb|X5|", "KX898160")),
                   c("AB033668", "MT1", "AB1", "X5", "KX898160"))
})

test_that(".mislabel_clean_groups() treats placeholders and non-binomials as missing", {
  d <- data.frame(species = c("Gelidium sp.", "Bangia sp. 2BAN", "Ulva lactuca", "X cf. y"),
                  family = c("Gelidiaceae", "incertae sedis", "Ulvaceae", "unk_family"),
                  stringsAsFactors = FALSE)
  out <- .mislabel_clean_groups(d, c("species", "family"))
  expect_identical(out$species, c(NA, NA, "Ulva lactuca", NA))
  expect_identical(out$family, c("Gelidiaceae", NA, "Ulvaceae", NA))
})

test_that(".mislabel_nearest_other() returns the closest non-member group from another batch", {
  dep <- .mk_profile_pool(); hits <- .mk_profile_hits(dep)
  nb <- .mislabel_nearest_other(hits, dep, c("AA101", "AA301"), c("species", "genus"))
  expect_identical(nb$species$B, c("Aus beta", "Bus delta"))   # congener at 95
  expect_identical(nb$genus$B, c("Bus", "Aus"))                 # other genus at 90
  # a reference whose only hits are its own batch has no nearest other group
  h2 <- hits[hits$q == "AA101" & hits$s %in% c("AA101"), ]
  nb2 <- .mislabel_nearest_other(h2, dep, "AA101", "species")
  expect_true(is.na(nb2$species$B))
})

test_that(".marker_resolution() resolves a cleanly separated marker at every rank", {
  dep <- .mk_profile_pool(); hits <- .mk_profile_hits(dep)
  r <- .marker_resolution(hits, dep, c("species", "genus", "family"))
  expect_equal(r$present$resolved[r$present$rank == "species"], 1)
  # species absent: its congener (95) is the nearest, so genus resolves
  expect_equal(r$absent$resolved[r$absent$rank == "genus"], 1)
  expect_false("species" %in% r$absent$rank)
})

test_that(".marker_resolution() calls a tie across species ambiguous and a swap wrong", {
  dep <- .mk_profile_pool(); hits <- .mk_profile_hits(dep)
  # Aus alpha ties with Aus beta at the top identity
  hits$pid[hits$q %in% dep$acc[dep$species == "Aus alpha"] & hits$s %in% dep$acc[dep$species == "Aus beta"]] <- 99
  # Bus gamma's nearest is Bus delta (a wrong call at species)
  hits$pid[hits$q %in% dep$acc[dep$species == "Bus gamma"] & hits$s %in% dep$acc[dep$species == "Bus delta"]] <- 100
  r <- .marker_resolution(hits, dep, c("species", "genus"))
  p <- r$present[r$present$rank == "species", ]
  expect_equal(p$ambiguous, 0.25)   # one of four species tied
  expect_equal(p$wrong, 0.25)       # one of four species misresolved
  expect_equal(r$present$resolved[r$present$rank == "genus"], 1)
})

test_that(".marker_resolution() drops excluded (screened-out) sequences from both sides", {
  dep <- .mk_profile_pool(); hits <- .mk_profile_hits(dep)
  hits$pid[hits$q == "AA101" & hits$s == "AA301"] <- 100   # a mislabel-like hit
  r_in <- .marker_resolution(hits, dep, "species")
  r_ex <- .marker_resolution(hits, dep, "species", exclude = "AA301")
  expect_lt(r_in$present$resolved, 1)
  expect_equal(r_ex$present$resolved, 1)
})

test_that(".reference_label_profile() classifies supported / cannot_discriminate / too_few / censored", {
  dep <- .mk_profile_pool(); hits <- .mk_profile_hits(dep)
  refs <- c("AA101", "AA201", "AA301")
  fake_stats <- data.frame(
    accession = rep(refs, 2), rank = rep(c("species", "genus"), each = 3),
    A = NA, B = c("Aus beta", "Aus alpha", NA, "Bus", "Bus", "Aus"),
    x = c(99, 95, 99, 95, 95, 95), x_batches = c(3, 3, 1, 3, 3, 3),
    y = c(95, 95, NA, 90, 90, 90), y_batches = c(3, 3, 0, 3, 3, 3),
    d = 95, d_batches = 3, class = "Cx", stringsAsFactors = FALSE)
  testthat::local_mocked_bindings(
    .mislabel_rank_statistics = function(hits, deposits, assign, rank, rank_system, exclude) {
      fake_stats[fake_stats$rank == rank, ]
    },
    .mislabel_lr_test = function(stats, rank_system, ...) {
      stats$status <- "tested"; stats$selected <- FALSE; stats$posterior <- 0.01
      attr(stats, "pi") <- 0; attr(stats, "guard") <- data.frame(cutoff = 2); stats
    },
    .test_reference_mislabels = function(stats_fun, ref_species, ...) {
      data.frame(accession = refs, rank = "species", A = NA, B = NA, posterior = NA,
                 action = "keep", reason = "not_selected")
    })
  out <- .reference_label_profile(hits, dep, refs, ref_species = c(AA101 = "Aus alpha"),
                                  rank_system = c("species", "genus"), quantum = 1, full_list = 3L)
  p <- out$profile
  o <- function(a, r) p$outcome[p$accession == a & p$rank == r]
  expect_identical(o("AA101", "species"), "supported")            # 99 vs 95
  expect_identical(o("AA201", "species"), "cannot_discriminate")  # 95 vs 95
  # AA301 has no other species among its hits but its list is "full" (>= 3)
  expect_identical(o("AA301", "species"), "supported")
  expect_true(p$censored_support[p$accession == "AA301" & p$rank == "species"])
  expect_identical(out$summary$label_confirmed_to[out$summary$accession == "AA101"], "species")
})

test_that(".reference_label_profile() gives identical results in parallel and serially", {
  skip_on_os("windows")
  dep <- .mk_profile_pool(); hits <- .mk_profile_hits(dep)
  refs <- dep$acc[c(1, 4, 7, 10)]
  testthat::local_mocked_bindings(
    .mislabel_lr_test = function(stats, rank_system, ...) {
      stats$status <- "tested"; stats$selected <- FALSE; stats$posterior <- 0.01
      attr(stats, "pi") <- 0; attr(stats, "guard") <- data.frame(cutoff = 2); stats
    },
    .test_reference_mislabels = function(stats_fun, ref_species, ...) {
      s <- stats_fun(character(0))
      data.frame(accession = unique(s$accession), rank = "species", A = NA, B = NA,
                 posterior = NA, action = "keep", reason = "not_selected")
    })
  a <- .reference_label_profile(hits, dep, refs, ref_species = character(0),
                                rank_system = c("species", "genus", "family"), quantum = 1, cores = 1L)
  b <- .reference_label_profile(hits, dep, refs, ref_species = character(0),
                                rank_system = c("species", "genus", "family"), quantum = 1, cores = 2L)
  expect_identical(a$profile, b$profile)
})
