# Test fixtures

`gnv_ds11_bestresult.json` and `gnv_ds1_9_11_allmatches.json` are trimmed copies of ONE recorded
Global Names Verifier response (POST /api/v1/verifications, 12 names, data sources 1, 9 and 11,
withAllMatches = true), made on 2026-11-13 under the maintainer's approval. Only the fields
`verify_taxon_names(return_ids = TRUE)` reads were kept. `gnv_ds11_bestresult.json` reshapes the
source-11 (GBIF Backbone) results into the `bestResult` form a `withAllMatches = false` call returns
(the Exact result where one exists, else the first). No test reaches the network.
