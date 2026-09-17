# Walk an R file's AST; for every call to an exported ecosystem function,
# report named arguments that are not in that function's formals.
pkgs <- c("TaxaTools","TaxaFetch","TaxaHabitat","TaxaMatch","TaxaLikely",
          "TaxaExpect","TaxaAssign","TaxaFlag","TaxaWizard")
suppressMessages(invisible(lapply(pkgs, function(p)
  tryCatch(library(p, character.only=TRUE), error=function(e)
    cat("  [could not load", p, "]\n")))))
own <- list()
for (p in pkgs) if (p %in% loadedNamespaces())
  for (f in getNamespaceExports(p)) if (is.null(own[[f]])) own[[f]] <- p

check_file <- function(path) {
  exprs <- tryCatch(parse(path), error=function(e) NULL)
  if (is.null(exprs)) { cat("  PARSE ERROR\n"); return(invisible()) }
  found <- list()
  walk <- function(e) {
    if (is.call(e)) {
      fn <- e[[1]]
      nm <- NULL
      if (is.symbol(fn)) nm <- as.character(fn)
      else if (is.call(fn) && length(fn)==3 && as.character(fn[[1]]) %in% c("::",":::"))
        nm <- as.character(fn[[3]])
      if (!is.null(nm) && nm %in% names(own)) {
        f <- tryCatch(get(nm, envir=asNamespace(own[[nm]])), error=function(e) NULL)
        if (is.function(f)) {
          fm <- names(formals(f))
          an <- names(e); an <- an[!is.na(an) & nzchar(an)]
          bad <- setdiff(an, fm)
          if (length(bad) && !("..." %in% fm))
            found[[length(found)+1]] <<- sprintf("%s::%s()  stale arg(s): %s",
              own[[nm]], nm, paste(bad, collapse=", "))
        }
      }
    }
    if (is.recursive(e)) for (i in seq_along(e))
      if (!is.null(e[[i]])) tryCatch(walk(e[[i]]), error=function(err) NULL)
  }
  for (ex in exprs) walk(ex)
  if (!length(found)) cat("  clean\n") else
    for (m in unique(unlist(found))) cat("  ", m, "\n", sep="")
}
for (p in commandArgs(trailingOnly=TRUE)) {
  cat("########", basename(p), "\n"); check_file(p)
}
