# kernel_branch.R
# TaxaAssign package
#
# The one place that knows which prior_branch values mean "this row is a
# kernel estimate from local occurrence records".

#' Branch Values Meaning "Kernel-Estimated Resident"
#'
#' `TaxaExpect::estimate_kernel_priors()` writes `prior_branch` as a constant
#' on every row it emits. On 2026-09-14 that constant was renamed
#' `"resident_observed"` -> `"kernel_estimated"`, because the old name
#' asserted an evidence claim the estimator never tested: the label is
#' written identically whether a row rests on 3,663 effective records or on
#' 0.0000 (44.9% of real PtConception 12S rows carried under one).
#'
#' Both strings are accepted wherever the branch is read, and that is
#' deliberate rather than transitional: every prior table checkpointed before
#' the rename -- on disk across four sites, several of them expensive to
#' regenerate -- carries the old string, and a reader that recognised only
#' the new one would silently treat those rows as an unknown branch. That is
#' exactly the class of silent reclassification this rename exists to stop.
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
