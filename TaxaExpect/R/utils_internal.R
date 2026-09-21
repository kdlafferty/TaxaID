# ==============================================================================
# Shared internal helpers used by multiple exported functions in this
# package: beta_mean()/beta_sd(), and the genus/family/order/class/phylum
# rank-column vector used to join taxonomy onto proxy prior rows.
# ==============================================================================

#' Beta distribution mean from alpha/beta
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_mean <- function(a, b) a / (a + b)

#' Beta distribution SD from alpha/beta
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_sd <- function(a, b) sqrt((a * b) / ((a + b)^2 * (a + b + 1)))

#' Rank columns used to join taxonomy onto anonymous/named proxy prior rows
#'
#' Deliberately excludes \code{kingdom} (rarely useful for grouping proxy
#' rows) and \code{species} (proxy rows never carry a species-level identity
#' -- either \code{taxon_name} is NA (dark-diversity proxies) or the row's
#' species-level name IS \code{taxon_name} already, not a separate rank
#' column). Ordered finest to coarsest, matching the order both consumers
#' use.
#' @noRd
.dark_diversity_rank_cols <- c("genus", "family", "order", "class", "phylum")
