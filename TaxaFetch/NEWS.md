# TaxaFetch 1.0.0

* Initial release.
* `check_geographic_outliers(on_cap = )` defaults to `"warn"`, the same default
  as the `get_gbif_occurrences(on_cap = )` it forwards to, so a plain call
  reports a truncated global cloud and keeps it. `"escalate"` -- which
  re-fetches each capped species through the GBIF download API, against the
  supplied credentials and producing a DOI to cite -- is requested explicitly.
  `on_cap` is one of the inputs to the verdict-cache key, so a verdict file
  stored under a different value is not served to a call that uses the default;
  the first such call recomputes it.
* An OpenAlex request failure reports a message with the API key replaced by
  `***REDACTED***`. OpenAlex takes the key as a URL query parameter, so a
  connection error raised by curl or httr2 can carry the full request URL into
  its condition message, and `literature_search()` surfaces that message to the
  caller. The redaction happens before the message is raised, so anything that
  captures those messages -- a log, a transcript, an issue report -- captures the
  placeholder rather than the key.
