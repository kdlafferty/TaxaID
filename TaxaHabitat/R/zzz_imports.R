# Package-wide import declarations for functions used in internal helpers.
#
# call_anthropic_api was imported here but never actually called anywhere in
# this package as a bare (unqualified) symbol -- TaxaHabitat's own functions
# never call an LLM provider directly (build_habitat_prompt() only builds
# prompt strings; the actual LLM call happens externally via
# TaxaTools::prompt_api()/call_*_api(), always namespace-qualified in this
# package's own docs and examples). Removed as confirmed-dead, per this
# ecosystem's own established convention (see TaxaHabitat/CLAUDE.md's
# 2026-07-28 session note for the precedent: an analogous unused rlang
# import was removed the same way). call_api was considered as a
# replacement per a reviewer suggestion, but is equally unused as a bare
# symbol here -- adding it would just create the same class of dead import.

#' @importFrom utils head
#' @importFrom stats aggregate
#' @importFrom TaxaTools %||%
NULL
