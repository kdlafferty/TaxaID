# Questions for the USGS review (security / software release)

Opened 2026-10-02 at the maintainer's request. One item per question, each with
what we know and what we do NOT know, so the reviewer is not asked to re-derive it.
Keep answers here as they arrive; this file is a release artefact of the 1.0 screen
and is NOT part of the shipped package.

---

## 1. The software-release DOI is a placeholder in all ten READMEs

`<https://doi.org/10.5066/xxxxxx>` appears in the citation block of the root README
and of all nine package READMEs:

> Lafferty, K.D., 2026, TaxaID: A modular R ecosystem for Bayesian taxonomic
> assignment: U.S. Geological Survey software release, <https://doi.org/10.5066/xxxxxx>.

It returns HTTP 404, and `R CMD check --as-cran` reports it among "possibly invalid
URLs", which is part of the one standing WARNING every package in this ecosystem
currently carries.

The maintainer's reading is that this is filled in at publication, when the release
DOI is minted. QUESTION FOR THE REVIEWER: is that correct, and is the placeholder
acceptable in the repository until then, or does the release process expect the
citation block to be absent (or to omit the DOI line) until a real DOI exists?
If it is filled at publication, who fills it -- the author or the release
coordinator -- and in all ten files or only the root README?

WHY IT IS WORTH ASKING RATHER THAN GUESSING: ten files is the kind of edit that is
easy to do once and miss on the tenth, so the answer determines whether we need a
check that fails when any README still says `xxxxxx`. If the answer is "filled at
publication", that check is cheap and I will add it to the release gate.

---

## 2. AI-use disclosure: is the per-package sentence required, and in what form?

Every one of the nine package READMEs ends its dependency section with:

> Developed with [Claude Code](https://claude.ai/code) (Anthropic PBC, San
> Francisco, California).

The root README carries a fuller, deliberate disclosure ("the TaxaID source code
was written with the assistance of Anthropic Claude models, used through Claude
Code. Claude Sonnet did the bulk of the development; Claude Opus and Claude Fable
also contributed. Because this assistance was continuous rather than confined to
particular functions, per-function annotation would imply a precision that does
not exist"), so disclosure here is a considered practice, not boilerplate -- and
the per-package sentence follows the same vendor-citation style the README uses for
R itself ("R Core Team ... Vienna, Austria").

So this is being KEPT, not stripped. Two narrower questions:

(a) Does the USGS release process have a required FORM for disclosing
generative-AI assistance in a software release (a specific statement, a specific
location, a Disclaimer-section requirement)? If so we should match it rather than
use our own wording.

(b) The hyperlink `https://claude.ai/code` returns HTTP 403 to automated
checkers (it resolves normally for a human; the host refuses non-browser agents).
It is the single URL `R CMD check` names by itself. We can keep the sentence and
drop the hyperlink, which clears the check and loses nothing a reader needs. Is
there any reason the URL must be present?

---

## 3. Which GitHub organisation should the release cite?

Every in-tree reference -- 28 of them across the root README, the nine package
READMEs, the `inst/CITATION` files and `DESCRIPTION` -- names
`github.com/kdlafferty/TaxaID`, which is also the configured `origin` remote and
resolves (HTTP 200). But this ecosystem's own CLAUDE.md records a 2026-09-13 change
updating all nine `inst/CITATION` files to `github.com/DOI-USGS/TaxaID`, and that
URL currently returns 404 -- so either the DOI-USGS repository does not exist yet,
or it exists privately, or that change was reverted or never reached these files.

QUESTION FOR THE REVIEWER: for a USGS software release, must the canonical
repository live under the DOI-USGS organisation, and if so is the migration part
of the release process (in which case all 28 references change at that point, and
the citation block's URL with them)? If the release can cite a personal-account
repository, nothing needs to change.

WHY IT MATTERS NOW RATHER THAN AT RELEASE: a reader who follows the CLAUDE.md
record would conclude the citations already point at DOI-USGS; they do not. One of
the two records is wrong and it is cheaper to find out which before the citation
block is frozen.

---

## 4. One dependency-citation link has an expired certificate

`https://insectapp.las.iastate.edu`, cited in `TaxaMatch/README.md`, fails with
libcurl error 60 -- the host is alive and serves content, but its TLS certificate
has expired ("Status without verification: OK"). Not our host and not ours to fix.
QUESTION: for a release, should a cited third-party resource whose certificate has
lapsed be kept as-is, replaced with a DOI or archival link, or dropped?

---

## Resolved, no reviewer time needed

The per-package AI-use disclosure sentence has been DE-LINKED at the maintainer's
decision (2026-10-02): the sentence stays in all nine package READMEs, the
hyperlink to `https://claude.ai/code` is gone. That clears the only URL
`R CMD check` named by itself while keeping the disclosure. Question 2(a) above --
whether USGS has a required FORM for the disclosure -- is still open.

A deep GitHub blob link in `TaxaMatch/README.md` returns HTTP 503 to automated
probing and looks broken; it is not. The repository root resolves (200) and the
anchor's target heading exists in the file (`## Reference Accession Quality
{#reference-accession-quality}`). GitHub refuses automated agents on blob paths.
Checked so that nobody spends time on it twice.

Four further URLs flagged by automated checking are publisher and vendor
bot-blocking and resolve normally for a human -- a PNAS Nexus DOI, a PeerJ
preprint, an OpenAlex settings page, and platform.openai.com. They are not
defects and need no reviewer time.
