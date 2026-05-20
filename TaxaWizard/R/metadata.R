#' Load Package Metadata Registry
#'
#' Reads per-package JSON metadata files from \code{inst/metadata/} and
#' assembles the type compatibility matrix used by the workflow engine.
#'
#' @param packages Character vector of package names to load. Default
#'   loads all available TaxaID packages.
#'
#' @return A named list of package metadata, each containing function
#'   signatures, input/output types, and scaling notes.
#' @noRd
.load_metadata <- function(packages = NULL) {

  metadata_dir <- system.file("metadata", package = "TaxaWizard")
  if (!nzchar(metadata_dir)) {
    stop("TaxaWizard metadata directory not found. Is the package installed?",
         call. = FALSE)
  }

  json_files <- list.files(metadata_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(json_files) == 0L) {
    stop("No metadata JSON files found in ", metadata_dir, call. = FALSE)
  }

  # Filter to requested packages if specified
  if (!is.null(packages)) {
    basenames <- tools::file_path_sans_ext(basename(json_files))
    keep <- basenames %in% packages
    json_files <- json_files[keep]
  }

  registry <- lapply(json_files, function(f) {
    jsonlite::fromJSON(f, simplifyVector = FALSE)
  })
  names(registry) <- tools::file_path_sans_ext(basename(json_files))

  registry
}


#' Compress Metadata for Prompt Injection
#'
#' Converts the full metadata registry into a token-efficient text
#' representation suitable for inclusion in the system prompt.
#'
#' @param registry Named list from \code{.load_metadata()}.
#' @return Character string: compact function registry table.
#' @noRd
.compress_metadata <- function(registry) {

  lines <- character()
  for (pkg_name in names(registry)) {
    pkg <- registry[[pkg_name]]
    lines <- c(lines, sprintf("## %s", pkg_name))

    for (fn in pkg$functions) {
      # One-line summary: function | input_type | output_type | description
      input_types  <- paste(vapply(fn$inputs, `[[`, "", "type"), collapse = ", ")
      output_type  <- fn$output$type %||% "none"
      lines <- c(lines, sprintf(
        "- %s(%s) -> %s | %s",
        fn$name, input_types, output_type, fn$description
      ))
    }
    lines <- c(lines, "")
  }

  paste(lines, collapse = "\n")
}
