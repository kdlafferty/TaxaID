# ---- cache-key hashing -------------------------------------------------------
# rlang::hash() serializes a character vector's ENCODING MARK along with its
# bytes, so the same text hashes differently depending on how it reached R.
# Measured 2026-11-09: one 46-byte string marked UTF-8 hashed to 01c63a8b...,
# and the identical bytes marked "unknown" to 435373cc.... A caller who runs a
# script with source(file) instead of source(file, encoding = "UTF-8") gets the
# second, so every key built from a non-ASCII string misses -- the whole cache
# at once, because one such string usually sits in every key. There is no error
# and nothing in the log but "0 from cache". One of these re-asked 61 names of
# a paid model and cost a run its call budget.
#
# enc2utf8() normalises the mark before hashing, and is a no-op both for ASCII
# and for strings already marked UTF-8, so keys written before this helper
# existed stay reachable. A test asserts that against a real pre-existing key.#
# Two limits, both measured, neither worked around. A data.frame key whose
# string columns differ only in their MARK still hashes two ways, because
# normalising a column reorders the frame's attributes and rlang::hash()
# serializes that order; no site keys a data.frame on a non-ASCII string, and
# the non-orphaning direction holds for every shape, which is the direction
# that can destroy a cache. names() and factor levels are not normalised
# either. The property is also stated for a UTF-8 native locale: in a C or
# Latin-1 session enc2utf8() transcodes an "unknown" string from the native
# encoding, so the guarantee does not carry there.
#
#' Normalise the strings inside a cache key before hashing
#'
#' Recursive on purpose: most of this package's cache keys are a `list()` of
#' fields, so normalising only the top level would leave the strings inside
#' untouched.
#'
#' @param x Any object. Character elements come back `enc2utf8()`-normalised,
#'   lists are walked element by element, anything else is returned unchanged.
#' @return `x`. Character vectors, and the character elements of plain, named,
#'   nested and classed lists, come back UTF-8-marked; **data.frame columns,
#'   `names()` and factor levels are not normalised** (see the note above), and
#'   anything already correctly marked is returned untouched rather than
#'   rebuilt.
#' @noRd
.cache_hash_input <- function(x) {
  if (is.character(x)) {
    return(enc2utf8(x))
  }
  if (is.list(x)) {
    # Assign only where normalising would actually change the hash, and touch
    # nothing else. Every blanket rebuild perturbs a data.frame key, measured:
    # lapply() drops all attributes but names; `x[] <-` reorders them
    # (names,class,row.names becomes names,row.names,class); and
    # `attributes(x) <- ` expands the compact row.names c(NA, -1L) to 1L.
    # rlang::hash() serializes all three, so each one would move an ASCII
    # key's hash and orphan its cache, which is the harm this helper exists to
    # prevent. `.verify_decisions_fingerprint()` hashes a data.frame, so it is
    # not hypothetical. Leaving an unchanged element alone keeps the object
    # bit-identical.
    for (i in seq_along(x)) {
      yi <- .cache_hash_input(x[[i]])
      if (!identical(rlang::hash(yi), rlang::hash(x[[i]]))) {
        x[[i]] <- yi
      }
    }
    return(x)
  }
  x
}

#' Hash a cache key independently of its strings' encoding marks
#'
#' A drop-in replacement for `rlang::hash()` at cache-key sites. For a key
#' holding only ASCII, or only strings already marked UTF-8, it returns exactly
#' what `rlang::hash()` returns.
#'
#' @param x The key: a single string, or a list of key fields.
#' @return A single character string, as `rlang::hash()` returns.
#' @noRd
.cache_hash <- function(x) {
  rlang::hash(.cache_hash_input(x))
}
