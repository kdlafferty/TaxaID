# Package-wide import declarations for functions used in internal helpers as
# bare (unqualified) symbols. TaxaHabitat's own functions never call an LLM
# provider directly -- build_habitat_prompt() only builds prompt strings; the
# actual LLM call happens externally via
# TaxaTools::prompt_api()/call_*_api(), always namespace-qualified in this
# package's own docs and examples -- so no LLM-call import belongs here.

#' @importFrom utils head
#' @importFrom stats aggregate
#' @importFrom TaxaTools %||%
NULL
