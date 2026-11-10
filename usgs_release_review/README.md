# USGS WERC software-release review

The formal review of this repository ahead of its USGS software release, kept
here so the record and the reviewer's own corrected files stay together. This
folder is deliberately **outside every package** -- it documents the release,
it is not part of any package's source.

Previously called `misc review docs/`, which undersold it badly enough that it
sat untracked and unexplained for months. Renamed 2026-09-14.

## Contents

| file | what it is |
|---|---|
| `WERCReview.docx` | the reviewer's comments |
| `WERC_Software_Checklist.pdf` | the WERC release checklist (moved out of `inst/`) |
| `USGS_Software_Releases_guidance.pdf` | USGS release guidance (moved out of `inst/`) |
| `reviewer_supplied_README.md` | the README the reviewer rewrote and supplied |
| `reviewer_supplied_code.json` | the `code.json` the reviewer supplied, on the USGS template |

The two supplied files are the reviewer's versions, kept as provenance for
changes already made in the live repository. They are **not** the live files:
the live ones are `README.md` and `code.json` at the repository root, and both
have moved on since (the live README, for example, corrects theta from
"species occurrence probability" to "expected species composition -- each
taxon's relative share of the detections", which the supplied copy predates).

## Status of the review's requests, checked 2026-09-14

| request | status |
|---|---|
| README title with a colon, not a dash | done |
| `code.json` on the USGS Software template, CC0 | done |
| Remove LICENSE and DISCLAIMER from each package folder | done, none remain |
| Remove the Disclaimer from each package README | done |
| `renv/` -- needed for publishing? | removed |
| `POLISHING_ROADMAP.md`, `TODO_PUBLICATION.md` | removed |
| `TaxaID_Git_Setup.md` | removed |
| `ecosystem_docs/INTRO.md` -- outdated, addresses only 4 packages | removed; the two surviving `inst/` copies were removed 2026-09-14 |
| `TaxaID_presentation.qmd` -- what is this? | untracked 2026-09-14; kept on disk, not shipped |
| "Any test files should be deleted for final publication" | **not done, deliberately** -- see below |
| `CLAUDE.md` placement; `inst/` -> `llm`? | open, not decided |
| Link `ECOSYSTEM_WORKFLOW.md` / `PACKAGE_SETUP.md` from the README | open, not decided |
| `DESCRIPTION.md` content folded into package READMEs | open, not decided |

### On deleting test files

Not done, and the recommendation is to push back rather than comply. The nine
packages carry roughly 12,700 tests; they are how several real defects were
caught during September 2026 alone, and a standard R package ships its
`tests/` directory. The request most likely meant scratch and development
scripts rather than the test suite, and that reading should be confirmed with
the reviewer before anything is deleted.

## Notes for the technical reviewer: security posture

Checked against the WERC criteria at `28f76da0`. Every **count** and every
**line citation** below was verified there, and a reviewer can check out that
commit to reproduce each one. The only commits between `28f76da0` and the
release tag change documentation, not code; if that is ever not so, this
statement is stale and must be re-verified before the tag.

Scope: the nine package `R/` trees, plus the test placeholders and process calls
noted where they fall outside it.

**This statement must be re-verified at each release commit, and that is part of
the release process rather than a courtesy.** Its predecessor named a commit,
was not re-stated across the merged pull requests that followed, and was
contradicted by its own reader's first grep; this statement was re-stated at
`28f76da0` after four line citations and one dependency sentence had drifted. Naming the commit is what makes the staleness
visible; removing the name would only hide it.

It is written down so the review does not have to rediscover it; where a check
found something to change, this says so rather than claiming nothing did.

**Where credentials come from.** Every credential is read through `Sys.getenv()`
and none is committed. Every key-shaped string in the repository is one of three
things: a documentation placeholder (`sk-ant-your-key-here`, `AIza...`),
`"fake-key"` in a test, or a deliberately distinctive test marker whose whole
purpose is to be searched for -- `"sk-ant-test-distinctive-marker-should-never-appear-0000"`
(`TaxaWizard/tests/testthat/test-pack.R:216`) and
`"sk-ant-TOTALLY-SECRET-VALUE-12345"` (`test-setup.R:81`), each set with
`Sys.setenv()` inside a test that then asserts the value does not reach an
output. They are shaped like keys on purpose; neither is a credential.

Twelve credential-bearing variables appear by name, in 36 call sites across the
nine `R/` trees:

| variable | sites | goes to |
|---|---|---|
| `NCBI_API_KEY` | 8 | NCBI E-utilities |
| `ENTREZ_KEY` | 5 | NCBI E-utilities (rentrez' own variable) |
| `INAT_API_TOKEN` | 5 | iNaturalist |
| `XAI_API_KEY` | 3 | xAI |
| `GBIF_USER` | 3 | GBIF (username) |
| `ANTHROPIC_API_KEY` | 3 | Anthropic |
| `OPENALEX_API_KEY` | 2 | OpenAlex |
| `OPENAI_API_KEY` | 2 | OpenAI |
| `GBIF_PWD` | 2 | GBIF (**password**) |
| `XC_API_KEY` | 1 | xeno-canto |
| `GEMINI_API_KEY` | 1 | Google Generative Language |
| `AZURE_OPENAI_API_KEY` | 1 | Azure OpenAI (DOI) |

`GBIF_EMAIL` (2 sites) and `NCBI_EMAIL` (1) sit beside them and are identifiers,
not secrets. **The arithmetic, so a reviewer's own grep reconciles:** a sweep of
`Sys\.getenv\("[A-Z_]*"` over the nine `R/` trees returns **42** literal hits:
**36** credential sites (the table), **3** identifier sites (`GBIF_EMAIL` 2,
`NCBI_EMAIL` 1), and **3** that are not credentials at all -- `TAXAID_ROOT`,
`HOME`, and `MY_KEY_VAR`, the last a variable name used as an example inside
roxygen (`TaxaTools/R/llm_api_utils.R:681`). 36 + 3 + 3 = 42.

**That list cannot be closed by grep, and the reason matters more than the
count.** Nine further call sites read a variable whose NAME is itself a value:
`Sys.getenv(key_var)` at `TaxaTools/R/call_api.R:121` and
`R/model_registry.R:393,500,586`; `Sys.getenv(p$key)` at `TaxaTools/R/zzz.R:25`
and `TaxaWizard/R/zzz.R:28`; `Sys.getenv(v)` at `TaxaWizard/R/setup.R:62`; and
two inside the text of a script TaxaWizard generates, at `R/shiny.R:1718,1730`.
The name comes either from the built-in provider table (`TaxaTools/R/zzz.R:17-20`)
or, for a caller-registered provider, from `prov_reg$api_key_var`, chosen at
`R/call_api.R:109` and `R/model_registry.R:386,488,576`.

`register_provider()` is exported and documents `api_key_var` as "Name of the
environment variable holding..." (`R/model_registry.R:731`), so **the set of
variables this software may read is extensible by the caller and no static
inventory of it can be complete.** What makes that safe is that the redaction
below matches on the key's VALUE, not on its variable name, so it covers a
caller-registered provider identically.

**Credentials in URLs: four cases, two handlings.** Anthropic, OpenAI, Azure and
xAI pass the key in a header (`x-api-key`, `Authorization: Bearer`, `api-key`).
Four places put a credential in a URL query string, each because the provider's
API requires it. Note that a one-line grep for `req_url_query(key` finds only
three of them: the fourth spreads its arguments over several lines, which is
worth saying because it is how this case was missed twice.

1. `TaxaTools/R/call_api.R:268` -- Gemini. A connection error raised by curl or
   httr2 can echo the full request URL into its condition message. The handler
   strips the key before anything is surfaced (`:747-755`):

   ```r
   msg <- conditionMessage(e)
   if (nzchar(api_key)) {
     msg <- gsub(api_key, "***REDACTED***", msg, fixed = TRUE)
   }
   ```

2. `TaxaTools/R/model_registry.R:191` -- `.fetch_gemini_models()`, the model-list
   request. It carries no redaction and does not need one: its
   `tryCatch(..., error = function(e) NULL)` discards the condition entirely and
   returns `character(0)`, so no message can reach a caller. The protection is
   suppression rather than redaction, which is worth stating because the two look
   different in a diff.

3. `TaxaFetch/R/literature_search.R:84` -- OpenAlex. Its handler used to
   re-raise `conditionMessage(e)` verbatim, so a connection error could have
   carried the key into a `stop()` message. The handler now strips the key
   (`:88-103`, the `gsub` at `:99`) by the same value-matching redaction as
   case 1, before re-raising.

4. `TaxaLikely/R/coverage.R:1605-1608` -- xeno-canto, `key = xc_key` inside a
   multi-line `req_url_query()`. Handled as case 2: `tryCatch(..., error =
   function(e) NULL)` at `:1611` discards the condition, so no message can carry
   the key.

Separately, `rentrez::set_entrez_key()` hands the NCBI key to rentrez, which
appends it to E-utilities URLs, at ten sites: `TaxaLikely/R/fetch.R:2032`,
`R/coverage.R:184,955`, `R/suggest_unreferenced_species.R:975`;
`TaxaMatch/R/blast_sequences.R:1962,2083,2237`,
`R/investigate_flagged_accession.R:93`, `R/evaluate_reference_accessions.R:576`,
`R/check_marker_mismatch.R:114`. rentrez owns the request and the error text from
that point, so the redaction above does not reach it; the exposure is an NCBI key
in a URL inside a third-party package's condition message.

**Outbound requests.** Three request builders (Anthropic, Gemini, OpenAI-compatible).
The optional `temperature` argument is validated -- rejected unless it is a single
finite non-negative number -- and is included in the request body only when it is not
`NULL`, so the default sends no temperature field at all. Note that some models reject
the parameter outright (HTTP 400, "temperature is deprecated for this model"), which
`call_api()` surfaces as the provider's own message.

**Process and dynamic-evaluation inventory.** Stated as a current inventory
rather than as "added none", so that re-checking it is a matter of re-running the
same greps:

* `system()` -- one: `TaxaFetch/R/plan_gbif_fetch.R:180`, `sysctl -n hw.memsize`.
* `system2()` -- eight, every one a fixed binary with a fixed argument vector and
  no interpolated user text: `TaxaLikely/R/build_sequence.R:1487` (`ps`),
  `R/matrix_size.R:147,150` (`vm_stat`, `powershell`),
  `TaxaMatch/R/blast_sequences.R:1536,1665` (`blastn -version`,
  `blastdbcmd -info`; the database path goes through `shQuote()`),
  `R/investigate_flagged_accession.R:241,250` (`blastdbcmd`, `makeblastdb`).
  The eighth, `TaxaWizard/R/setup.R:449`, is the one whose binary name is not a
  literal: it and its version flag are read from the package's own shipped
  `inst/setup/requirements.json` (`system.file("setup", ...)`, hand-kept), and
  the binary must already resolve through `Sys.which()` before it is run. Still
  no user-supplied text, but "fixed binary" would overstate it.
* `eval(parse(text = ))` -- four, all in `TaxaWizard/R/shiny.R:285,291,318,1476`,
  acting on the app's own parameter fields as its `:1866` comment records, not on
  anything a remote client supplies.
* **Bare `eval()`** -- on this software's own formals defaults, never on supplied
  text: `TaxaAssign/R/generate_report.R:253` evaluates its own `default_model`
  default, falling back to `as.character()` on error; and
  `TaxaMatch/R/evaluate_reference_accessions.R:89,93-99` evaluate this function's
  own `formals()` to report the defaults it ran under. Listed because a reviewer
  grepping `eval(` rather than `eval(parse(` finds these, and a statement that
  mentions only the latter reads as incomplete.
* `eval(` also appears in `TaxaWizard` as **text rather than as a call**: in the
  scripts and apps it generates (`R/output.R:320,380`, `R/shiny.R:1210,1630`),
  in one line of commentary it writes into generated output (`R/shiny.R:1866`)
  and in one source comment (`R/shiny.R:1598`). Those are strings and comments;
  the four real `eval(parse())` sites are the ones listed above. A reviewer who
  greps `eval(` in `R/shiny.R` finds eight hits, and this accounts for all of
  them.

* **`parse(text = )` without `eval()`** -- two, both parse-only: at
  `TaxaWizard/R/shiny.R:413` a user-supplied script is parsed with
  `keep.source = TRUE` to read its source references, and the expressions are
  never evaluated; at `R/validate.R:137` the package parses its own `inst/`
  snippets to check they are syntactically valid. Parsing is not evaluation, but
  the same grep finds both, so both are named.
* No `eval.parent()`. No deserialization of external data: `readRDS` reads only
  this software's own file formats, including at caller-named paths --
  `TaxaWizard/R/cli.R:275` reads a wizard session object and
  `TaxaHabitat/R/spatial_review_decisions.R:60` a decisions object. The path is
  the caller's; the format is ours.

**File writes.** Every cache is opt-in through a caller-supplied `cache_dir`, except
TaxaWizard's workflow registry and TaxaTools' model registry, both of which use a
fixed path documented in the root README's caching table.

Cache filenames fall into two groups, and the protection differs. The
grid/kernel caches build their names from numeric hashes
(`%010.0f-%010.0f-%06d`), so no caller-supplied text reaches the path at all.
The reference-metadata cache does put the queried taxon name in the filename
(`TaxaLikely:::.ref_cache_stem()`), and what makes that safe is sanitisation
rather than hashing: `gsub("[^A-Za-z0-9]", "_", name)` admits only letters,
digits and underscore, so a name cannot contribute `/`, `.` or `..` and cannot
traverse out of `cache_dir`. The rest of that filename is generated -- length
and date bounds as integers, the rank system lower-cased and hyphen-joined, a
resolved numeric taxid, and an eight-character hexadecimal digest of the search
term -- and `.ref_cache_grammar()` asserts the whole shape, with a test that
generates names over a grid of argument combinations and requires every one to
match. A path this function cannot produce is also the definition of an
evictable file, so the grammar does double duty as a filename invariant and as
the eviction proof.

**Cache keys.** Keys are hashed through `.cache_hash()`, three internal copies
(`TaxaTools`, `TaxaFetch`, `TaxaLikely` `R/cache_key.R`) that normalise string
encodings before `rlang::hash()`. They read no environment variable, run no
process and make no request.

**Dependencies and licences.** The 1.0 cycle added no `Imports` or `Depends`
entry to any package's `DESCRIPTION`. It added one `Suggests` entry: `withr` in
`TaxaLikely` (commit `5995c1e1`), used only by a test, and already listed by
`TaxaTools`, `TaxaMatch` and `TaxaHabitat`. So no new third-party package is
installed for a user, and no new runtime surface exists to assess. All nine packages are `License: CC0`, matching `code.json`'s
`CC0-1.0`. The USGS provisional disclaimer is present in the root README, and
`code.json` carries `status: Preliminary`.

## `WERC_README_template.md`

The WERC-supplied README template, moved here from the repository root's
`inst/` on the maintainer's instruction. It is a **blank template**, not a
description of this software: its title line reads `ADD SOFTWARE TITLE
(TEMPLATE)`, it carries a placeholder DOI twice, and its two image paths
(`media/usgs_green.png`, `media/orcid.gif`) resolve to nothing in this
repository and did so before the move.

It was shipping inside the `TaxaID` meta-package, so a reviewer opening the
package's own `inst/README.md` was told the software had no title. Moved
rather than deleted because it is the template the release is written
against, and left byte-for-byte unedited because it is a supplied artifact --
the same treatment as `reviewer_supplied_README.md`. The repository's real
front page is the root `README.md`, which is unaffected.

## Related, deliberately NOT moved here

- `inst/Code and Domain Review 2.Rmd` -- a *different* review (the per-package
  code and domain review by Micah Wright). It is cited by ten files, including
  each package's own `inst/*_review_response.md`, so it stays where those
  references point.
- Each package's `inst/*_review_response.md` -- responses to that code review,
  not to this release review. They stay with their packages.

The written response to this release review is `RESPONSE_to_release_review.md`
in this folder.

## AI use, for the release record

The USGS policy on disclosing artificial-intelligence use in scientific
products (Survey Manual 502.4 and 502.6; Office of Science Quality and
Integrity guidance) asks a software release to name each AI tool with its
version, the purpose and extent of its use, and the dates, and to carry the
non-endorsement disclaimer wherever a trade, firm or product name appears.

Where that statement lives in this repository:

- The **root `README.md`**, section "Use of Large Language Models", carries the
  full statement: the models and versions, the period, what the assistance
  covered, and that the author reviewed the code and takes responsibility for
  it. It also distinguishes the three separate things an LLM does here --
  inside the software, in writing the code, and in assisting the user -- which
  a reviewer should not conflate.
- **Each package's `README.md`** carries the same statement in short form plus
  the non-endorsement disclaimer, because each one names commercial LLM
  providers.
- The model record is checkable rather than asserted: nearly every non-merge
  commit in this repository names the model that contributed to it in a
  `Co-Authored-By` trailer -- 1,759 of 1,821 at `77aa7471`, counted with
  `git log --no-merges --grep='Co-Authored-By: Claude'`. The remaining 62 carry
  no trailer, and no merge commit carries one.

Two things are deliberately NOT here, and are noted so their absence is not
read as an omission:

- `WERC_README_template.md` and `reviewer_supplied_README.md` are the
  reviewer's own files, kept as the record of what was supplied. The template
  has a disclaimer section but no AI section; it is not edited here.
- `code.json` carries the AI statement appended to its existing `description`,
  not in a field of its own. Whether the federal source-code metadata schema
  would accept a new field was NOT verified, so none was added; the existing
  free-text field needs no schema change.

The IPDS record for the release needs its own statement, which the policy
templates as: "AI-assisted coding tools [name and version of tools used] were
employed to generate code used in [describe usage]. All code was reviewed,
tested, and validated by the authors to ensure correctness and
reproducibility."

AI tools are not authors of this software.
