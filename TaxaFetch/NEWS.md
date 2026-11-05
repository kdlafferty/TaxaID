# TaxaFetch 1.0.0

* Initial release.
* An OpenAlex request failure reports a message with the API key replaced by
  `***REDACTED***`. OpenAlex takes the key as a URL query parameter, so a
  connection error raised by curl or httr2 can carry the full request URL into
  its condition message, and `literature_search()` surfaces that message to the
  caller. The redaction happens before the message is raised, so anything that
  captures those messages -- a log, a transcript, an issue report -- captures the
  placeholder rather than the key.
