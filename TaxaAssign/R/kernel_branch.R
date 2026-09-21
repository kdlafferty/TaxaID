# kernel_branch.R
# TaxaAssign package
#
# The one place that knows which prior_branch values mean "this row is a
# kernel estimate from local occurrence records".

#' Branch Values Meaning "Kernel-Estimated Resident"
#'
#' `TaxaExpect::estimate_kernel_priors()` writes `prior_branch` as
#' `"kernel_estimated"` on every row it emits -- chosen over the also-accepted
#' `"resident_observed"` (see below) because a name asserting the row's
#' residency was "observed" would carry an evidence claim the estimator never
#' tests: the label is written identically whether a row rests on 3,663
#' effective records or on 0.0000 (44.9% of real PtConception 12S rows carry
#' under one).
#'
#' Both strings are accepted wherever the branch is read, and permanently
#' rather than as a migration window: prior tables already on disk across
#' several sites, some expensive to regenerate, carry one string or the
#' other, and a reader that recognised only one would silently treat the
#' other's rows as an unknown branch -- exactly the class of silent
#' reclassification this dual acceptance is meant to prevent.
#'
#' Membership in this branch says only WHICH GENERATOR produced the row. It
#' says nothing about how much evidence stands behind it; that is
#' `effective_records`, which spans ~10 orders of magnitude within this one
#' branch. A consumer wanting an evidence claim must threshold it -- see
#' [posterior_consensus()]'s `min_effective_records`.
#'
#' @noRd
.KERNEL_BRANCH <- c("kernel_estimated", "resident_observed")

#' Is This prior_branch Value a Kernel-Estimated Resident Row?
#'
#' @param x Character vector of `prior_branch` values.
#' @return Logical vector, `FALSE` for `NA`.
#' @noRd
.is_kernel_branch <- function(x) {
  !is.na(x) & x %in% .KERNEL_BRANCH
}
