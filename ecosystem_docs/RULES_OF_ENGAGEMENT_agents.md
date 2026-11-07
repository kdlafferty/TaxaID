# Rules of engagement for agents working in TaxaID

Context about *what the packages do* is generated: `llm_prompts/CONTEXT_<pkg>.md`
per package plus `CONTEXT_TaxaID.md`, regenerated with
`TaxaWizard::workflow_export_prompts()` and guarded byte-for-byte by
`TaxaWizard/tests/testthat/test-pack.R`. Read those for behaviour.

This file is the other half: the constraints. Breaking one of these causes damage
that a test suite does not catch.

## The repository

1. **Never switch branches in the shared checkout.** Other sessions have files
   open in it. Use `git worktree add`; the shared stack means never bare
   `git stash` / `git stash pop` either -- prefer a WIP commit, or
   `git stash push -u -m "<tag>"` and `git stash apply <sha>`.
2. **Check `git status` before `git add`.** Another session's work may be in the
   tree.
3. **This git is 2.15.0.** There is no `git worktree remove`; use `rm -rf` then
   `git worktree prune`.
4. **A push is outward-facing.** `main` is public. Pushing needs the maintainer's
   direct word, and an approval relayed by another agent does not substitute for
   it. If your own permission layer blocks a push, that is the answer -- do not
   route it through another session, tool or host.
5. **`placeholder_setup_report` defaults to `TRUE`; still pass it explicitly on a
   repository regen.** With `FALSE`, `workflow_export_prompts()` writes
   `llm_prompts/SETUP_REPORT.md` as a real setup check for the machine that ran
   it -- session type and every installed package with its local build
   timestamp -- over the committed placeholder. This repository is public. The
   default now protects that case, but the regen is the call where a wrong value
   publishes a machine inventory, so state the intent rather than relying on a
   default someone may change. Use `workflow_export_prompts("llm_prompts",
   overwrite = TRUE, placeholder_setup_report = TRUE)` and read the diff before
   staging.

## Installing and running R

6. **Never install a package while any R-family process is alive** (`R`,
   `Rscript`, `rsession`, `radian`, `Rterm`), and never beside a live `blastn`.
   `load_all()`, `test()`, `check()` and `document()` are safe beside a live run;
   installing is not.
7. **Size an `.rds` before reading it**: `gzip -dc f.rds | wc -c`. On-disk size
   understates the loaded object badly -- 419 MB on disk has been 9.4 GB loaded.
   Two large reads in one process stack their peaks.
8. **Stay at or below 6 GB and run sequentially** unless the maintainer has
   raised it. Measure a slice before promising a memory budget.
9. **Bare `Rscript` outside the project root does not pick up `R_LIBS_USER`.**
   Start with
   `.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))`.
10. **`blastn` must be 2.16.0** from `~/opt/ncbi-blast-2.16.0+/bin`.

## What may change

11. **No new exported function without the maintainer's explicit yes.** List the
    name and full signature and wait. An exports diff cannot see a new *argument*
    on an existing function -- diff signatures, not just names.
12. **No dated or historical prose in user-facing documentation.** Roxygen,
    package READMEs and vignettes describe what the code does now, not what
    it used to do or when it changed. No "Session N", no "previously", no "no
    longer", no "legacy", no measurement dates. `CLAUDE.md`, `ecosystem_docs/`
    and `inst/*_review_response.md` are where history belongs.

    **`NEWS.md` is exempt, because saying what changed is its job.** A release
    note may say "previously", "no longer" or "withdraws a documented
    guarantee" where that is the information a reader needs -- whether to
    re-run something, whether a column moved, whether a guarantee they relied
    on is gone. What NEWS may not do is pad: "the rest of the class stays
    `zooplankton` as before" says nothing that "stays `zooplankton`" does not.
    Keep the comparison when it carries information and drop it when it does
    not.

    **The AI-use disclosure is exempt, and its dates are required.** The USGS
    policy on disclosing AI use in scientific products
    (Survey Manual 502.4 and 502.6) requires each tool's name and version, the
    purpose and extent of its use, and **the dates**. Every package README and
    the root README carry that statement, dates included. A sweep for dated
    prose must not strip it: removing those dates breaks a federal disclosure
    requirement, not a style rule. The same goes for the non-endorsement
    disclaimer that accompanies it.
13. **Decisions are learned from the data, never hard-coded per marker.** A rule
    that names 12S, 18S or COI, or that hard-codes a threshold, is wrong even if
    it fits. Any tier must be learned, with evidence that it carries signal.
14. **Errors over counts.** The maintainer would rather report fewer species than
    report a wrong one. Say so when a change trades the two.
15. **Guards are general methods, not dataset patches.** If it only works on this
    run's data, it is not finished.

## How to report

16. **Verify against the generated artefact, not the source you edited.** A
    roxygen claim is not visible until you check the `.Rd`, and a pack claim is
    not visible until you grep the pack. Per function the pack carries the
    signature, `\title`, `\description` **as its first paragraph only and at
    most 600 characters** (`TaxaWizard/R/registry.R:466`), then the
    `\arguments` table, `\value`, `@details` and **every titled `@section`,
    all four in full** (`R/pack.R:374-390`; `\value` is deliberately uncapped,
    and `registry.R:468-481` records why -- a prefix of an enumeration is not a
    shorter version of it but a wrong one). So the only thing shortened is the
    description, and a
    measurement buried in `@details` DOES reach the pack, and thence any model
    advising a user: there are 132 `#### Details` sections in the committed pack
    and `"Measured on"` appears in seven of the nine `CONTEXT_*.md` files.
    Regenerate and grep before saying a caveat is visible -- or that one is not.
17. **Measure at the published unit.** A defect that consensus absorbs before the
    output is not a defect in the output; a defect that only appears there is
    still real. Check that your proxy *can* fire before comparing groups.
18. **Report test passes from the tip that will merge**, and run the CI check
    invocation itself:
    `rcmdcheck::rcmdcheck(path = p, args = c("--no-manual", "--as-cran"), build_args = "--no-manual", error_on = "error")`.
    Run it last, on exactly what merges -- editing the tree after `R CMD build`
    has made its tarball invalidates the run.
19. **Clock times come from `date`,** never from extrapolation.
20. **Scripts load installed packages, not folders.** `load_all()` is for
    development. A production script uses `library(<pkg>)` and records what it
    loaded -- an install carries no commit, so a namespace code digest or a
    recorded commit is the only provenance there is. Pin to a commit, never to a
    directory, and only to a commit that is reachable on the remote.

21. **A change to user-visible behaviour adds a NEWS line, in the same pull
    request.** `<pkg>/NEWS.md`, under the heading that matches the change. CI
    does not check this -- the pack and the README inventory are the only
    generated artefacts it guards -- so nothing will stop a behaviour change
    shipping unrecorded, and one already did: a reference-cache key change
    meant every cached taxon re-fetched on the next run, with no entry saying
    why. User-visible means a caller can observe it: returned columns or rows,
    messages, file names, defaults, or work the user must redo. An entry may
    say what the behaviour changed FROM where that is what the reader needs --
    rule 12's ban on historical prose does not reach `NEWS.md`, which exists to
    record change. Say it because it is informative, not as filler.
