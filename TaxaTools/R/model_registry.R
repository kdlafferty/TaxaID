# ==============================================================================
# model_registry.R
# TaxaTools -- LLM model registry, tier resolution, and provider model discovery
#
# Exported functions:
#   list_models()          Show current tier->model mapping for detected providers
#   refresh_models()       Re-discover models from provider APIs; update local cache
#   set_model()            Pin a specific model version for reproducibility
#   model_cache_info()     Show local cache path, age, and session source
#   register_provider()    Add a custom OpenAI-compatible provider for this session
#
# Internal helpers (@noRd):
#   .registry_env              Session cache environment
#   .load_bundled_registry()   Read inst/model_tiers.json (shipped with package)
#   .local_cache_path()        Path to persistent per-user JSON cache
#   .load_local_cache()        Read persistent cache (NULL if missing/unreadable)
#   .save_local_cache()        Write persistent cache (warns on failure)
#   .get_registry()            Load registry into session -- local cache first,
#                              then bundled fallback (lazy, once per session)
#   .fetch_anthropic_models()  Query Anthropic /v1/models endpoint
#   .fetch_gemini_models()     Query Gemini /v1beta/models endpoint
#   .fetch_openai_models()     Query OpenAI /v1/models endpoint; filter chat models
#   .fetch_azure_models()      Query Azure /openai/models endpoint
#   .apply_tier_patterns()     Match sorted model IDs to fast/mid/top tiers
#   .resolve_model()           Full resolution chain: pin -> session cache ->
#                              provider API -> bundled fallback
#
# Resolution order (fastest to slowest, most specific to most general):
#   1. set_model() session pin          -- explicit reproducibility override
#   2. Session discovery cache          -- from a previous .resolve_model() call
#   3. Provider /models API             -- live, newest-first; cached into (2)
#   4. Bundled inst/model_tiers.json    -- ships with package; warn if stale
# ==============================================================================


# ------------------------------------------------------------------------------
# Session cache environment
# Slots:
#   $session_pins   named list  provider.tier -> model name  (from set_model())
#   $discovered     named list  provider      -> c(fast=, mid=, top=)
#   $registry       list        loaded JSON registry
#   $registry_source character  "local_cache" | "bundled"
#   $registry_loaded logical    TRUE once .get_registry() has run
# ------------------------------------------------------------------------------

.registry_env <- new.env(parent = emptyenv())


# ------------------------------------------------------------------------------
# JSON I/O
# ------------------------------------------------------------------------------

#' @noRd
.load_bundled_registry <- function() {
  path <- system.file("model_tiers.json", package = "TaxaTools")
  if (!nzchar(path) || !file.exists(path)) {
    stop(
      "TaxaTools: inst/model_tiers.json not found. ",
      "Reinstalling TaxaTools should fix this."
    )
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#' @noRd
.local_cache_path <- function() {
  file.path(tools::R_user_dir("TaxaTools", "cache"), "model_cache.json")
}

#' @noRd
.load_local_cache <- function() {
  path <- .local_cache_path()
  if (!file.exists(path)) return(NULL)
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) {
      warning(
        "TaxaTools: could not read local model cache at ", path,
        ". Using bundled defaults.",
        call. = FALSE
      )
      NULL
    }
  )
}

#' @noRd
.save_local_cache <- function(data) {
  path <- .local_cache_path()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tryCatch(
    jsonlite::write_json(data, path, pretty = TRUE, auto_unbox = TRUE),
    error = function(e) {
      warning(
        "TaxaTools: could not write model cache to ", path,
        ". Changes will not persist across sessions.",
        call. = FALSE
      )
    }
  )
}


# ------------------------------------------------------------------------------
# Registry loader (lazy, once per session)
# ------------------------------------------------------------------------------

#' @noRd
.get_registry <- function() {

  if (isTRUE(.registry_env$registry_loaded)) {
    return(.registry_env$registry)
  }

  # Tier patterns ALWAYS come from the bundled inst/model_tiers.json.
  # This ensures that updates to patterns (via devtools::install() or a PR to
  # the GitHub JSON) take effect immediately without clearing the local cache.
  #
  # The local cache only contributes fallback_models (discovered model names
  # from previous refresh_models() calls). This lets the package skip live API
  # queries in subsequent sessions while still using up-to-date patterns.
  reg <- .load_bundled_registry()

  local <- .load_local_cache()
  if (!is.null(local)) {
    cache_date <- tryCatch(
      as.Date(local[["_meta"]][["version"]]),
      error = function(e) as.Date("2000-01-01")
    )
    age_days <- as.numeric(Sys.Date() - cache_date)

    if (age_days <= 90) {
      # Overlay only fallback_models from local cache -- never tier_patterns
      for (prov in names(local$providers %||% list())) {
        if (!is.null(reg$providers[[prov]]) &&
            !is.null(local$providers[[prov]]$fallback_models)) {
          reg$providers[[prov]]$fallback_models <-
            local$providers[[prov]]$fallback_models
        }
      }
      .registry_env$registry_source <- "local_cache"
    } else {
      warning(sprintf(
        "TaxaTools: model cache is %d days old. Run refresh_models() for the latest, or reinstall TaxaTools for updated bundled defaults.",
        round(age_days)
      ), call. = FALSE)
      .registry_env$registry_source <- "bundled"
    }
  } else {
    .registry_env$registry_source <- "bundled"
  }

  .registry_env$registry        <- reg
  .registry_env$registry_loaded <- TRUE
  reg
}


# ------------------------------------------------------------------------------
# Provider model discovery
# All functions return a character vector of model IDs sorted newest-first,
# or character(0) on any failure (network error, auth error, etc.).
# Timeouts are short (10 s) -- these are metadata calls, not inference calls.
# ------------------------------------------------------------------------------

#' @noRd
.fetch_anthropic_models <- function(api_key) {
  resp <- tryCatch(
    httr2::request("https://api.anthropic.com/v1/models") |>
      httr2::req_headers(
        "x-api-key"         = api_key,
        "anthropic-version" = "2023-06-01"
      ) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(character(0))

  parsed <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  # Anthropic returns data sorted newest-first already
  vapply(parsed$data %||% list(), function(m) m$id %||% "", character(1))
}

#' @noRd
.fetch_gemini_models <- function(api_key) {
  resp <- tryCatch(
    httr2::request("https://generativelanguage.googleapis.com/v1beta/models") |>
      httr2::req_url_query(key = api_key) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(character(0))

  parsed <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  models <- parsed$models %||% list()

  # Filter for generateContent-capable models only
  gen_models <- Filter(function(m) {
    methods <- vapply(
      m$supportedGenerationMethods %||% list(),
      function(x) as.character(x),
      character(1)
    )
    "generateContent" %in% methods
  }, models)

  # Strip "models/" prefix; sort alphabetically descending (version numbers sort correctly)
  ids <- vapply(gen_models, function(m) sub("^models/", "", m$name %||% ""), character(1))
  sort(ids[nzchar(ids)], decreasing = TRUE)
}

#' @noRd
.fetch_openai_models <- function(api_key) {
  resp <- tryCatch(
    httr2::request("https://api.openai.com/v1/models") |>
      httr2::req_headers("Authorization" = paste("Bearer", api_key)) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(character(0))

  parsed  <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  models  <- parsed$data %||% list()

  # Keep only chat-capable models (gpt-* and o-series).
  # Exclude specialized non-chat variants (TTS, transcription, search, image).
  # Note: newer OpenAI models use owned_by = "system", not "openai" -- do not
  # filter on owned_by.
  chat_models <- Filter(function(m) {
    id <- m$id %||% ""
    grepl("^gpt-|^o[0-9]", id, perl = TRUE) &&
      !grepl("tts|transcribe|diarize|search|dall-e|whisper|embed|instruct",
             id, ignore.case = TRUE)
  }, models)

  # Sort by creation timestamp descending (newest first)
  if (length(chat_models) > 1L) {
    ts          <- vapply(chat_models, function(m) m$created %||% 0L, numeric(1))
    chat_models <- chat_models[order(ts, decreasing = TRUE)]
  }

  vapply(chat_models, function(m) m$id %||% "", character(1))
}

#' @noRd
.fetch_azure_models <- function(api_key, endpoint_template) {
  # Build the /models URL from the endpoint template
  # Template: https://host/openai/deployments/{model}/chat/completions?api-version=X
  # Models:   https://host/openai/models?api-version=X
  base_url    <- sub("/openai/deployments/.*", "", endpoint_template)
  api_version <- regmatches(
    endpoint_template,
    regexpr("api-version=[^&]+", endpoint_template)
  )
  if (length(api_version) == 0L || !nzchar(api_version)) return(character(0))

  url  <- paste0(base_url, "/openai/models?", api_version)
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_headers(`api-key` = api_key) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) NULL   # connection refused when not on DOI network
  )
  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(character(0))

  parsed <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  models <- parsed$data %||% list()
  vapply(models, function(m) m$id %||% "", character(1))
}


#' @noRd
.fetch_openai_compat_models <- function(api_key, models_endpoint) {
  # Generic fetch for any OpenAI-compatible /v1/models endpoint.
  # Used by registered custom providers (type = "openai_compatible").
  resp <- tryCatch(
    httr2::request(models_endpoint) |>
      httr2::req_headers("Authorization" = paste("Bearer", api_key)) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(character(0))

  parsed <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  models <- parsed$data %||% list()

  if (length(models) > 1L) {
    ts     <- vapply(models, function(m) m$created %||% 0L, numeric(1))
    models <- models[order(ts, decreasing = TRUE)]
  }

  ids <- vapply(models, function(m) m$id %||% "", character(1))
  ids[nzchar(ids)]
}


# ------------------------------------------------------------------------------
# Tier pattern matching
# model_ids  -- character vector sorted newest-first
# patterns   -- list(fast=list(include, exclude), mid=..., top=...)
# Returns    -- named character vector, e.g. c(fast="...", mid="...", top="...")
# ------------------------------------------------------------------------------

#' @noRd
.apply_tier_patterns <- function(model_ids, patterns) {
  result <- character(0)

  for (tier_name in c("fast", "mid", "top")) {
    p <- patterns[[tier_name]]
    if (is.null(p)) next

    candidates <- model_ids

    # Must match include pattern
    if (!is.null(p$include) && nzchar(p$include %||% "")) {
      candidates <- candidates[
        grepl(p$include, candidates, perl = TRUE, ignore.case = TRUE)
      ]
    }

    # Must NOT match exclude pattern
    if (!is.null(p$exclude) && nzchar(p$exclude %||% "")) {
      candidates <- candidates[
        !grepl(p$exclude, candidates, perl = TRUE, ignore.case = TRUE)
      ]
    }

    # First surviving candidate is newest (pre-sorted)
    if (length(candidates) > 0L) {
      result[tier_name] <- candidates[[1L]]
    }
  }

  result
}


# ------------------------------------------------------------------------------
# Resolution chain
# provider  -- "anthropic" | "gemini" | "openai" | "azure"
# tier      -- "fast" | "mid" | "top"
# Returns a single model ID string; stops on complete failure
# ------------------------------------------------------------------------------

#' @noRd
.resolve_model <- function(provider, tier) {

  # --- 1. Session pin (set_model()) -----------------------------------------
  pin_key <- paste0(provider, ".", tier)
  pin     <- .registry_env$session_pins[[pin_key]]
  if (!is.null(pin) && nzchar(pin)) return(pin)

  # --- 2. Session discovery cache -------------------------------------------
  disc <- .registry_env$discovered[[provider]]
  if (!is.null(disc) && !is.null(disc[[tier]]) && nzchar(disc[[tier]])) {
    return(disc[[tier]])
  }

  # --- 3. Provider /models API ----------------------------------------------
  registry  <- .get_registry()
  prov_reg  <- registry$providers[[provider]]

  if (!is.null(prov_reg)) {
    # Registered providers store api_key_var; built-ins use hardcoded lookup
    key_var <- prov_reg$api_key_var %||% switch(provider,
      anthropic = "ANTHROPIC_API_KEY",
      gemini    = "GEMINI_API_KEY",
      openai    = "OPENAI_API_KEY",
      azure     = "AZURE_OPENAI_API_KEY",
      ""
    )
    api_key <- Sys.getenv(key_var)

    if (nzchar(api_key)) {
      endpoint_tpl <- prov_reg$endpoint_template %||% ""

      model_ids <- tryCatch({
        if (identical(prov_reg$type, "openai_compatible")) {
          ep <- prov_reg$models_endpoint %||% ""
          if (nzchar(ep)) .fetch_openai_compat_models(api_key, ep) else character(0)
        } else {
          switch(provider,
            anthropic = .fetch_anthropic_models(api_key),
            gemini    = .fetch_gemini_models(api_key),
            openai    = .fetch_openai_models(api_key),
            azure     = .fetch_azure_models(api_key, endpoint_tpl),
            character(0)
          )
        }
      }, error = function(e) character(0))

      if (length(model_ids) > 0L) {
        patterns <- prov_reg$tier_patterns

        if (!is.null(patterns)) {
          # Standard providers: apply tier patterns
          tier_map <- .apply_tier_patterns(model_ids, patterns)
        } else {
          # Azure: no tier patterns -- all tiers map to first available deployment
          tier_map <- stats::setNames(
            rep(model_ids[[1L]], 3L),
            c("fast", "mid", "top")
          )
        }

        # Cache for this session
        if (is.null(.registry_env$discovered)) .registry_env$discovered <- list()
        .registry_env$discovered[[provider]] <- tier_map

        if (!is.null(tier_map[[tier]]) && nzchar(tier_map[[tier]])) {
          return(tier_map[[tier]])
        }
      }
    }
  }

  # --- 4. Bundled fallback --------------------------------------------------
  fallback <- prov_reg$fallback_models[[tier]]
  if (!is.null(fallback) && nzchar(fallback)) {
    return(fallback)
  }

  stop(sprintf(
    ".resolve_model: no model found for provider '%s', tier '%s'. Check your API key and run refresh_models().",
    provider, tier
  ))
}


# ==============================================================================
# Exported functions
# ==============================================================================


#' List Current LLM Model Tier Assignments
#'
#' Shows the model name that each tier (\code{fast}, \code{mid}, \code{top})
#' resolves to for each provider whose API key is set. Also shows the source
#' of the assignment: a session pin, a live API discovery, or the bundled
#' fallback.
#'
#' Models are discovered lazily -- the first call for a provider triggers a
#' live \code{/models} API query and caches the result for the session. Use
#' \code{\link{refresh_models}} to force re-discovery.
#'
#' @param provider Character vector. Provider name(s) to show. Default
#'   \code{NULL} shows all providers with an API key set in the environment.
#'
#' @return A data frame (invisibly) with columns \code{provider}, \code{tier},
#'   \code{model}, \code{source}.
#'
#' @seealso \code{\link{refresh_models}}, \code{\link{set_model}},
#'   \code{\link{model_cache_info}}
#' @export
#'
#' @examples
#' \dontrun{
#' list_models()
#' list_models("anthropic")
#' }
list_models <- function(provider = NULL) {

  registry <- .get_registry()

  # Build key_vars dynamically (includes registered custom providers)
  key_vars <- vapply(names(registry$providers), function(p) {
    prov_reg <- registry$providers[[p]]
    prov_reg$api_key_var %||% switch(p,
      anthropic = "ANTHROPIC_API_KEY",
      gemini    = "GEMINI_API_KEY",
      openai    = "OPENAI_API_KEY",
      azure     = "AZURE_OPENAI_API_KEY",
      ""
    )
  }, character(1))

  # Default: only providers with keys set
  if (is.null(provider)) {
    provider <- names(key_vars)[
      vapply(key_vars, function(k) nzchar(Sys.getenv(k)), logical(1))
    ]
  }

  valid <- intersect(provider, names(registry$providers))
  if (length(valid) == 0L) {
    message("list_models: no matching providers found.")
    return(invisible(data.frame()))
  }

  rows <- lapply(valid, function(prov) {
    prov_reg <- registry$providers[[prov]]

    do.call(rbind, lapply(c("fast", "mid", "top"), function(tier) {
      pin_key <- paste0(prov, ".", tier)

      if (!is.null(.registry_env$session_pins[[pin_key]]) &&
          nzchar(.registry_env$session_pins[[pin_key]])) {
        model_name <- .registry_env$session_pins[[pin_key]]
        src        <- "pinned"
      } else {
        disc <- .registry_env$discovered[[prov]]
        if (!is.null(disc) && tier %in% names(disc) && nzchar(disc[[tier]] %||% "")) {
          model_name <- disc[[tier]]
          src        <- "discovered"
        } else {
          model_name <- prov_reg$fallback_models[[tier]] %||% NA_character_
          src        <- "bundled"
        }
      }

      data.frame(
        provider = prov,
        tier     = tier,
        model    = model_name %||% NA_character_,
        source   = src,
        stringsAsFactors = FALSE
      )
    }))
  })

  result <- do.call(rbind, rows)
  print(result, row.names = FALSE)
  invisible(result)
}


#' Refresh LLM Model Discovery from Provider APIs
#'
#' Queries each provider's \code{/models} endpoint to find the latest available
#' models, applies tier patterns to assign \code{fast}/\code{mid}/\code{top}
#' tiers, and saves the results to the local persistent cache. Only providers
#' with an API key set in the environment are queried.
#'
#' Call this function when a model name becomes stale (e.g., a
#' \code{404 deprecated} error) or after adding a new API key.
#'
#' @param providers Character vector. Provider names to refresh. Default
#'   \code{NULL} refreshes all providers with keys set.
#'
#' @return A data frame of updated tier assignments (invisibly), as from
#'   \code{\link{list_models}}.
#'
#' @seealso \code{\link{list_models}}, \code{\link{set_model}},
#'   \code{\link{model_cache_info}}
#' @export
#'
#' @examples
#' \dontrun{
#' refresh_models()
#' refresh_models("gemini")
#' }
refresh_models <- function(providers = NULL) {

  registry <- .get_registry()

  # Build key_vars dynamically (includes registered custom providers)
  key_vars <- vapply(names(registry$providers), function(p) {
    prov_reg <- registry$providers[[p]]
    prov_reg$api_key_var %||% switch(p,
      anthropic = "ANTHROPIC_API_KEY",
      gemini    = "GEMINI_API_KEY",
      openai    = "OPENAI_API_KEY",
      azure     = "AZURE_OPENAI_API_KEY",
      ""
    )
  }, character(1))

  keyed <- names(key_vars)[
    vapply(key_vars, function(k) nzchar(Sys.getenv(k)), logical(1))
  ]

  to_refresh <- if (!is.null(providers)) intersect(providers, keyed) else keyed

  if (length(to_refresh) == 0L) {
    message("refresh_models: no providers with API keys found.")
    return(invisible(NULL))
  }

  message(sprintf(
    "refresh_models: querying %s...",
    paste(to_refresh, collapse = ", ")
  ))

  # Reset registry so .get_registry() re-reads bundled patterns fresh.
  # This ensures any JSON updates (via install or GitHub fetch) take effect.
  .registry_env$registry_loaded <- FALSE
  .registry_env$registry        <- NULL

  # Clear session discovery cache for these providers (force API re-query)
  for (p in to_refresh) {
    .registry_env$discovered[[p]] <- NULL
  }

  # Trigger discovery for each provider + tier
  for (p in to_refresh) {
    found <- character(0)
    for (tier in c("fast", "mid", "top")) {
      model <- tryCatch(
        .resolve_model(p, tier),
        error = function(e) NA_character_
      )
      if (!is.na(model)) {
        found <- c(found, sprintf("%s=%s", tier, model))
      }
    }
    if (length(found) > 0L) {
      message(sprintf("  %s: %s", p, paste(found, collapse = ", ")))
    } else {
      message(sprintf("  %s: discovery failed -- using bundled fallbacks", p))
    }
  }

  # Persist: save a copy of the registry with updated fallback_models so that
  # next session can skip the API query if the cache is recent
  cache <- .get_registry()  # get a copy
  for (p in to_refresh) {
    disc <- .registry_env$discovered[[p]]
    if (!is.null(disc) && length(disc) > 0L) {
      for (tier in names(disc)) {
        cache$providers[[p]]$fallback_models[[tier]] <- disc[[tier]]
      }
    }
  }
  cache[["_meta"]][["version"]]    <- format(Sys.Date())
  cache[["_meta"]][["updated_by"]] <- "refresh_models()"
  .save_local_cache(cache)

  invisible(list_models(to_refresh))
}


#' Pin a Specific Model Version for Reproducibility
#'
#' Overrides dynamic tier resolution for the current R session. Use at the top
#' of an analysis script to lock the exact model version, ensuring results can
#' be reproduced regardless of what the provider currently returns as
#' \code{latest}.
#'
#' Pins are session-only and do not affect the persistent cache. To unpin,
#' restart R or call \code{set_model(provider, tier, NULL)}.
#'
#' @param provider Character. Provider name: \code{"anthropic"},
#'   \code{"gemini"}, \code{"openai"}, or \code{"azure"}.
#' @param tier Character. Tier to pin: \code{"fast"}, \code{"mid"}, or
#'   \code{"top"}.
#' @param model Character. Exact model identifier to use, or \code{NULL} to
#'   remove an existing pin.
#'
#' @return The model string invisibly.
#'
#' @seealso \code{\link{list_models}}, \code{\link{refresh_models}}
#' @export
#'
#' @examples
#' \dontrun{
#' # At the top of a reproducible analysis script:
#' set_model("anthropic", "mid", "claude-sonnet-4-5")
#' set_model("gemini",    "mid", "gemini-2.5-flash")
#'
#' # Remove a pin:
#' set_model("anthropic", "mid", NULL)
#' }
set_model <- function(provider, tier, model) {

  valid_providers <- names(.get_registry()$providers)
  valid_tiers     <- c("fast", "mid", "top")

  if (!provider %in% valid_providers) {
    stop(sprintf(
      "set_model: unknown provider '%s'. Valid options: %s",
      provider, paste(valid_providers, collapse = ", ")
    ))
  }
  if (!tier %in% valid_tiers) {
    stop(sprintf(
      "set_model: unknown tier '%s'. Valid options: %s",
      tier, paste(valid_tiers, collapse = ", ")
    ))
  }

  pin_key <- paste0(provider, ".", tier)

  if (is.null(model)) {
    .registry_env$session_pins[[pin_key]] <- NULL
    message(sprintf("set_model: pin removed for %s/%s.", provider, tier))
    return(invisible(NULL))
  }

  if (!is.character(model) || length(model) != 1L || !nzchar(model)) {
    stop("set_model: 'model' must be a non-empty character string or NULL.")
  }

  if (is.null(.registry_env$session_pins)) .registry_env$session_pins <- list()
  .registry_env$session_pins[[pin_key]] <- model
  message(sprintf(
    "set_model: %s/%s pinned to '%s' for this session.",
    provider, tier, model
  ))
  invisible(model)
}


#' Show Model Cache Information
#'
#' Reports the location and age of the local persistent model cache, and the
#' source used by the current session (\code{"local_cache"} or
#' \code{"bundled"}).
#'
#' @return A named list (invisibly) with elements \code{path}, \code{exists},
#'   \code{age_days}, and \code{source}.
#'
#' @seealso \code{\link{refresh_models}}, \code{\link{list_models}}
#' @export
#'
#' @examples
#' \dontrun{
#' model_cache_info()
#' }
model_cache_info <- function() {
  path      <- .local_cache_path()
  exists    <- file.exists(path)
  age_days  <- if (exists) {
    as.numeric(difftime(Sys.time(), file.info(path)$mtime, units = "days"))
  } else {
    NA_real_
  }
  src <- .registry_env$registry_source %||% "(not yet loaded this session)"

  cat(sprintf("Local cache path : %s\n", path))
  cat(sprintf("Cache exists     : %s\n", exists))
  if (exists) cat(sprintf("Cache age        : %.0f days\n", age_days))
  cat(sprintf("Session source   : %s\n", src))

  invisible(list(path = path, exists = exists, age_days = age_days, source = src))
}


#' Register a Custom OpenAI-Compatible LLM Provider
#'
#' Adds a custom provider to the session registry so that
#' \code{\link{list_models}}, \code{\link{refresh_models}}, and
#' \code{\link{set_model}} work with it alongside the built-in providers.
#' Registered providers are also picked up automatically by
#' \code{\link{call_openai_api}} when its \code{base_url} matches.
#'
#' Registered providers are session-only and do not persist to disk.
#' Add the call to \code{~/.Rprofile} or the top of your analysis script
#' for automatic re-registration.
#'
#' @param name Character. Short identifier for the provider, e.g.
#'   \code{"xai"}, \code{"groq"}, \code{"mistral"}.
#' @param api_key_var Character. Name of the environment variable holding
#'   the API key, e.g. \code{"XAI_API_KEY"}. Set the key in
#'   \code{~/.Renviron}: \code{XAI_API_KEY=xai-...}.
#' @param base_url Character. Base URL of the OpenAI-compatible API, e.g.
#'   \code{"https://api.x.ai"}. The \code{/v1/models} and
#'   \code{/v1/chat/completions} paths are appended automatically.
#' @param fallback_models Named list with elements \code{fast}, \code{mid},
#'   and \code{top}. Model names to use when live discovery is unavailable.
#'   Example: \code{list(fast = "grok-3-mini", mid = "grok-3", top = "grok-3")}.
#' @param tier_patterns Named list. Regex include/exclude patterns for tier
#'   assignment from a live \code{/v1/models} response. Same structure as
#'   \code{inst/model_tiers.json}:
#'   \preformatted{
#'   list(
#'     fast = list(include = "mini",    exclude = NULL),
#'     mid  = list(include = "grok-3$", exclude = "mini"),
#'     top  = list(include = "heavy",   exclude = NULL)
#'   )
#'   }
#'   \code{NULL} (default): all tiers map to the first discovered model
#'   (no tier differentiation).
#'
#' @return The \code{name} string invisibly.
#'
#' @seealso \code{\link{call_openai_api}}, \code{\link{list_models}},
#'   \code{\link{refresh_models}}, \code{\link{set_model}}
#' @export
#'
#' @examples
#' \dontrun{
#' # Register xAI Grok (OpenAI-compatible)
#' Sys.setenv(XAI_API_KEY = "xai-...")
#' register_provider(
#'   name            = "xai",
#'   api_key_var     = "XAI_API_KEY",
#'   base_url        = "https://api.x.ai",
#'   fallback_models = list(fast = "grok-3-mini", mid = "grok-3", top = "grok-3"),
#'   tier_patterns   = list(
#'     fast = list(include = "mini",    exclude = NULL),
#'     mid  = list(include = "grok-3$", exclude = "mini"),
#'     top  = list(include = NULL,      exclude = NULL)
#'   )
#' )
#'
#' # After registration, tier resolution works automatically
#' call_openai_api("What phylum do sea urchins belong to?",
#'   tier     = "mid",
#'   base_url = "https://api.x.ai",
#'   api_key  = Sys.getenv("XAI_API_KEY")
#' )
#'
#' # Or as an llm_fn closure for use anywhere in the ecosystem
#' my_grok <- function(p, ...) call_openai_api(p,
#'   tier     = "mid",
#'   base_url = "https://api.x.ai",
#'   api_key  = Sys.getenv("XAI_API_KEY")
#' )
#' options(TaxaID.llm_fn = my_grok)
#'
#' # Inspect
#' list_models("xai")
#' refresh_models("xai")
#' }
register_provider <- function(
    name,
    api_key_var,
    base_url,
    fallback_models = list(),
    tier_patterns   = NULL
) {

  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    stop("register_provider: 'name' must be a non-empty character string.")
  }
  if (!is.character(api_key_var) || length(api_key_var) != 1L || !nzchar(api_key_var)) {
    stop("register_provider: 'api_key_var' must be a non-empty character string.")
  }
  if (!is.character(base_url) || length(base_url) != 1L || !nzchar(base_url)) {
    stop("register_provider: 'base_url' must be a non-empty character string.")
  }
  if (name %in% c("anthropic", "gemini", "openai", "azure")) {
    stop(sprintf(
      "register_provider: '%s' is a built-in provider. Use set_model() to pin models or refresh_models() to update.",
      name
    ))
  }

  base_clean      <- gsub("/$", "", base_url)
  models_endpoint <- paste0(base_clean, "/v1/models")

  # Ensure registry is loaded, then add provider to session copy
  reg <- .get_registry()
  reg$providers[[name]] <- list(
    api_key_var     = api_key_var,
    base_url        = base_clean,
    models_endpoint = models_endpoint,
    auth_type       = "bearer",
    tier_patterns   = tier_patterns,
    fallback_models = as.list(fallback_models),
    type            = "openai_compatible"
  )
  .registry_env$registry        <- reg
  .registry_env$discovered[[name]] <- NULL  # clear any stale entry

  message(sprintf(
    "register_provider: '%s' registered (key var: %s, base URL: %s).",
    name, api_key_var, base_clean
  ))
  invisible(name)
}
