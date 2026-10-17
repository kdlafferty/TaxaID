# pool_unreferenced.R
# TaxaAssign package
#
# Pooling of named unreferenced rows into their ring row, used inside
# compute_posterior(). Internal; documented in compute_posterior()'s
# "Pooled unreferenced rows" section.

# A pooled row is one whose point posterior is below this. Same value as
# posterior_consensus()'s `min_posterior` default, so a row pooled here could
# not have entered the plausible set on its own at the default.
.POOL_MIN_POSTERIOR <- 0.05

# Point posterior (the arithmetic compute_posterior() uses before any
# closed-genus move): normalised likelihood times prior, normalised again,
# within each observation. Returns the posterior and a per-row flag for
# observations where it is not well defined (non-finite inputs, or a zero
# sum, which normalize_vec() turns into a uniform fallback).
.pt_plain <- function(obs, lik, prior) {
  f <- factor(obs, levels = unique(obs))
  s <- as.vector(rowsum(lik, f, na.rm = TRUE))[as.integer(f)]
  nl <- ifelse(s == 0, NA_real_, lik / s)
  raw <- nl * prior
  tot <- as.vector(rowsum(raw, f, na.rm = TRUE))[as.integer(f)]
  post <- raw / tot
  bad <- !is.finite(lik) | !is.finite(prior)
  unit_bad <- as.vector(rowsum(as.integer(bad), f))[as.integer(f)] > 0L |
    s == 0 | tot == 0 | !is.finite(tot)
  list(post = post, unit_bad = unit_bad)
}

# Pool named unreferenced rows into their ring rows.
# Returns list(df, pooled) where `pooled` is the data frame behind
# attr(, "pooled_rows") (zero rows when nothing was pooled).
.pool_unreferenced_rows <- function(df, use_beta) {
  empty <- data.frame(
    observation_id = character(0), ring_taxon = character(0),
    taxon_name = character(0), prior_mean = numeric(0),
    posterior_point_est = numeric(0), stringsAsFactors = FALSE
  )
  n <- nrow(df)
  need <- c("hypothesis_type", "taxon_name", "taxon_name_rank")
  if (n == 0L || !all(need %in% names(df))) {
    return(list(df = df, pooled = empty))
  }
  obs <- as.character(df$observation_id)
  ht <- as.character(df$hypothesis_type)
  rk <- as.character(df$taxon_name_rank)
  tn <- as.character(df$taxon_name)
  lik <- df$score_likelihood
  pm <- df$prior_mean

  mix_cols <- c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent")
  is_mix <- if (all(mix_cols %in% names(df))) {
    !is.na(df$prior_mix_w) & !is.na(df$prior_mix_theta_present) &
      !is.na(df$prior_mix_theta_absent)
  } else {
    rep(FALSE, n)
  }
  closed <- if ("constraint_applied" %in% names(df)) {
    df$constraint_applied %in% "census_closed_genus_relabeled"
  } else {
    rep(FALSE, n)
  }

  isU <- .is_unreferenced_type(ht)
  named <- ht %in% c("unreferenced_species", "unreferenced_genus") &
    rk %in% "species" & !is.na(tn)
  ring <- isU & !(rk %in% "species") & !is.na(rk) & !is.na(tn)
  if (!any(named) || !any(ring)) {
    return(list(df = df, pooled = empty))
  }

  pt <- .pt_plain(obs, lik, pm)
  cand <- named & !is_mix & !closed & !pt$unit_bad & pt$post < .POOL_MIN_POSTERIOR &
    is.finite(pm)
  if (!any(cand)) {
    return(list(df = df, pooled = empty))
  }

  # --- ring lookup, ambiguous (duplicate) keys resolve to NA ----------------
  look <- function(key_rows, key_cand) {
    dup <- duplicated(key_rows) | duplicated(key_rows, fromLast = TRUE)
    idx <- which(ring)
    k <- key_rows[ring]
    d <- dup[ring]
    m <- match(key_cand, k)
    m[!is.na(m) & d[m]] <- NA_integer_
    idx[m]
  }
  k3 <- function(o, h, r, t) paste(o, h, r, t, sep = "\r")
  k2 <- function(o, r, t) paste(o, r, t, sep = "\r")
  k1 <- function(o, t) paste(o, t, sep = "\r")
  ci <- which(cand)
  ring_of <- rep(NA_integer_, n)

  has_scope <- all(c("unreferenced_scope", "unreferenced_scope_rank") %in% names(df))
  sc <- sr <- rep(NA_character_, n)
  if (has_scope) {
    sc <- as.character(df$unreferenced_scope)
    sr <- as.character(df$unreferenced_scope_rank)
  }
  gen_col <- if ("genus" %in% names(df)) as.character(df$genus) else rep(NA_character_, n)
  gen <- ifelse(is.na(gen_col) | !nzchar(gen_col), sub("\\s.*$", "", tn), gen_col)
  fam <- if ("family" %in% names(df)) as.character(df$family) else rep(NA_character_, n)

  # (a) scope-carrying rows
  a <- ci[!is.na(sc[ci])]
  if (length(a)) {
    with_rank <- a[!is.na(sr[a])]
    if (length(with_rank)) {
      ring_of[with_rank] <- look(
        k2(obs, rk, tn), k2(obs[with_rank], sr[with_rank], sc[with_rank])
      )
    }
    no_rank <- a[is.na(sr[a])]
    if (length(no_rank)) {
      ring_of[no_rank] <- look(k1(obs, tn), k1(obs[no_rank], sc[no_rank]))
    }
  }
  # (b) TaxaLikely::expand() copies: ring named by the row's genus / family
  b <- ci[is.na(sc[ci])]
  bs <- b[ht[b] == "unreferenced_species" & !is.na(gen[b])]
  if (length(bs)) {
    ring_of[bs] <- look(k3(obs, ht, rk, tn), k3(obs[bs], "unreferenced_species", "genus", gen[bs]))
  }
  bg <- b[ht[b] == "unreferenced_genus" & !is.na(fam[b])]
  if (length(bg)) {
    ring_of[bg] <- look(k3(obs, ht, rk, tn), k3(obs[bg], "unreferenced_genus", "family", fam[bg]))
  }

  ok <- !is.na(ring_of[ci])
  ci <- ci[ok]
  ri <- ring_of[ci]
  # the ring must be poolable into and share the likelihood
  good <- !is_mix[ri] & !closed[ri] & is.finite(pm[ri]) & is.finite(lik[ri]) &
    !pt$unit_bad[ri] & obs[ri] == obs[ci] &
    abs(lik[ci] - lik[ri]) <= 1e-12
  ci <- ci[good]
  ri <- ri[good]
  if (!length(ci)) {
    return(list(df = df, pooled = empty))
  }

  # --- second pass: sub-ring genus node guard (ring coarser than genus) ------
  coarse <- !(rk[ri] %in% c("genus", "species"))
  if (any(coarse)) {
    gk <- paste(ri, gen[ci], sep = "\r")
    gsum <- tapply(pt$post[ci], gk, sum)
    heavy <- coarse & gsum[gk] >= .POOL_MIN_POSTERIOR
    ci <- ci[!heavy]
    ri <- ri[!heavy]
  }
  if (!length(ci)) {
    return(list(df = df, pooled = empty))
  }

  # --- Beta moment matching per ring ----------------------------------------
  uri <- unique(ri)
  sum_m <- tapply(pm[ci], match(ri, uri), sum)
  M <- pm[uri] + as.vector(sum_m)
  if (any(M >= 1)) {
    drop_ring <- uri[M >= 1]
    keepc <- !(ri %in% drop_ring)
    ci <- ci[keepc]
    ri <- ri[keepc]
    if (!length(ci)) {
      return(list(df = df, pooled = empty))
    }
    uri <- unique(ri)
    sum_m <- tapply(pm[ci], match(ri, uri), sum)
    M <- pm[uri] + as.vector(sum_m)
  }
  pooled_mass <- as.vector(sum_m)
  pooled_n <- as.vector(table(factor(match(ri, uri), levels = seq_along(uri))))
  pooled_names <- vapply(seq_along(uri), function(j) {
    paste(tn[ci[match(ri, uri) == j]], collapse = "; ")
  }, character(1))

  new_alpha <- new_beta <- NULL
  if (use_beta) {
    a0 <- df$prior_alpha
    b0 <- df$prior_beta
    v_row <- function(i) pm[i] * (1 - pm[i]) / (a0[i] + b0[i] + 1)
    vsum <- v_row(uri)
    vadd <- tapply(v_row(ci), match(ri, uri), sum)
    vtot <- vsum + as.vector(vadd)
    finite_in <- is.finite(vtot) & is.finite(a0[uri]) & is.finite(b0[uri])
    phi <- pmax(M * (1 - M) / vtot - 1, 1e-6)
    new_alpha <- ifelse(finite_in, M * phi, a0[uri])
    new_beta <- ifelse(finite_in, (1 - M) * phi, b0[uri])
  }

  # --- apply ------------------------------------------------------------------
  out <- df
  prev_n <- if ("pooled_n" %in% names(df)) df$pooled_n else rep(NA_integer_, n)
  prev_mass <- if ("pooled_prior_mass" %in% names(df)) df$pooled_prior_mass else rep(NA_real_, n)
  prev_taxa <- if ("pooled_taxa" %in% names(df)) df$pooled_taxa else rep(NA_character_, n)
  pn <- ifelse(is.na(prev_n), ifelse(ring, 0L, NA_integer_), as.integer(prev_n))
  pmass <- ifelse(is.na(prev_mass), ifelse(ring, 0, NA_real_), prev_mass)
  ptax <- as.character(prev_taxa)
  pn[uri] <- pn[uri] + as.integer(pooled_n)
  pmass[uri] <- pmass[uri] + pooled_mass
  ptax[uri] <- ifelse(is.na(ptax[uri]), pooled_names, paste(ptax[uri], pooled_names, sep = "; "))
  out$pooled_n <- pn
  out$pooled_prior_mass <- pmass
  out$pooled_taxa <- ptax
  out$prior_mean[uri] <- M
  if (use_beta) {
    out$prior_alpha[uri] <- new_alpha
    out$prior_beta[uri] <- new_beta
  }
  pooled <- data.frame(
    observation_id = obs[ci], ring_taxon = tn[ri], taxon_name = tn[ci],
    prior_mean = pm[ci], posterior_point_est = pt$post[ci],
    stringsAsFactors = FALSE
  )
  keep <- rep(TRUE, n)
  keep[ci] <- FALSE
  out <- out[keep, , drop = FALSE]
  rownames(out) <- NULL

  # --- exactness check ---------------------------------------------------------
  pt2 <- .pt_plain(as.character(out$observation_id), out$score_likelihood, out$prior_mean)
  expect <- pt$post
  add <- tapply(pt$post[ci], ri, sum)
  expect[as.integer(names(add))] <- expect[as.integer(names(add))] + as.vector(add)
  expect <- expect[keep]
  if (!isTRUE(all(abs(pt2$post - expect) <= 1e-12))) {
    stop(
      "Internal error in pooling unreferenced rows: a point posterior changed ",
      "by more than 1e-12 (max difference ",
      format(max(abs(pt2$post - expect), na.rm = TRUE)),
      "). Please report this.",
      call. = FALSE
    )
  }
  list(df = out, pooled = pooled)
}


#' Give a compute_posterior() result its fixed pooled-row schema
#'
#' Adds `pooled_n`, `pooled_prior_mass` and `pooled_taxa` when absent: `0`,
#' `0` and `NA` on a ring row (a generic unreferenced row above species, the
#' only rows that can pool), `NA` on every other row. Existing values are
#' kept. Also guarantees the `pooled_rows` (possibly 0-row) and
#' `pooled_min_posterior` attributes.
#' @noRd
.ensure_pooled_schema <- function(out) {
  n <- nrow(out)
  ring <- if (all(c("hypothesis_type", "taxon_name_rank", "taxon_name") %in% names(out))) {
    rk <- as.character(out$taxon_name_rank)
    .is_unreferenced_type(as.character(out$hypothesis_type)) &
      !(rk %in% "species") & !is.na(rk) & !is.na(out$taxon_name)
  } else {
    rep(FALSE, n)
  }
  if (!"pooled_n" %in% names(out)) out$pooled_n <- ifelse(ring, 0L, NA_integer_)
  if (!"pooled_prior_mass" %in% names(out)) out$pooled_prior_mass <- ifelse(ring, 0, NA_real_)
  if (!"pooled_taxa" %in% names(out)) out$pooled_taxa <- rep(NA_character_, n)
  if (is.null(attr(out, "pooled_rows"))) {
    attr(out, "pooled_rows") <- data.frame(
      observation_id = character(0), ring_taxon = character(0),
      taxon_name = character(0), prior_mean = numeric(0),
      posterior_point_est = numeric(0), stringsAsFactors = FALSE
    )
  }
  if (is.null(attr(out, "pooled_min_posterior"))) {
    attr(out, "pooled_min_posterior") <- .POOL_MIN_POSTERIOR
  }
  out
}
