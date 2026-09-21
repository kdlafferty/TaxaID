# kernel_branch.R
# TaxaAssign package
#
# The one place that knows which prior_branch value means "this row is a
# kernel estimate from local occurrence records".

#' Branch Value Meaning "Kernel-Estimated Resident"
#'
#' `TaxaExpect::estimate_kernel_priors()` writes `prior_branch` as
#' `"kernel_estimated"` on every row it emits. The label says only that a
#' kernel estimator produced the row; it makes no evidence claim, since the
#' string is written identically whether a row rests on 3,663 effective
#' records or on 0.0000 (44.9% of real PtConception 12S rows carry under
#' one).
#'
#' `"kernel_estimated"` is the only accepted spelling. `.is_kernel_branch()`
#' stops on any `prior_branch` value outside the full accepted set (see
#' `.PRIOR_BRANCH_LEVELS`) instead of silently treating it as unknown or as
#' an alias -- a cached prior table carrying a pre-1.0 label must error, not
#' vanish from downstream filters.
#'
#' Membership in this branch says only WHICH GENERATOR produced the row. It
#' says nothing about how much evidence stands behind it; that is
#' `effective_records`, which spans ~10 orders of magnitude within this one
#' branch. A consumer wanting an evidence claim must threshold it -- see
#' [posterior_consensus()]'s `min_effective_records`.
#'
#' @noRd
.KERNEL_BRANCH <- "kernel_estimated"

#' All Accepted `prior_branch` Values
#'
#' The full set of `prior_branch` labels a 1.0 producer writes: the kernel
#' estimate itself (`.KERNEL_BRANCH`), plus the two non-kernel branches --
#' `TaxaExpect::apply_undetected_evidence()` and
#' `generate_undetected_diversity()` write `"resident_undetected"`;
#' `generate_domestic_food_priors()` writes `"transport"`. Used to name the
#' accepted set in the error `.is_kernel_branch()` raises on an unrecognised
#' value.
#'
#' @noRd
.PRIOR_BRANCH_LEVELS <- c("kernel_estimated", "resident_undetected", "transport")

#' Is This prior_branch Value a Kernel-Estimated Resident Row?
#'
#' Stops if `x` contains any non-`NA` value outside `.PRIOR_BRANCH_LEVELS`
#' -- an unrecognised `prior_branch` value is a schema error, most likely a
#' prior table written under a pre-1.0 label, and must fail loudly rather
#' than silently read as "not a kernel-estimated row".
#'
#' @param x Character vector of `prior_branch` values.
#' @return Logical vector, `FALSE` for `NA`.
#' @noRd
.is_kernel_branch <- function(x) {
  unrecognised <- setdiff(unique(x[!is.na(x)]), .PRIOR_BRANCH_LEVELS)
  if (length(unrecognised) > 0) {
    stop(
      "Unrecognised prior_branch value(s): ",
      paste(unrecognised, collapse = ", "),
      ". Accepted values are: ",
      paste(.PRIOR_BRANCH_LEVELS, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  !is.na(x) & x == .KERNEL_BRANCH
}
