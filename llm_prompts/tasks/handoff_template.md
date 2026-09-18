# TaxaID workflow hand-off

Fill this in at the end of a chat and give it to the user. The next chat should start
with `START_HERE.md` plus this note. Assume the next chat remembers nothing else.

## Where we are

- **Goal:** <one sentence: what the user wants out, and from what data>
- **Interface mode:** <agent | chat>
- **Stages done:** <list, e.g. "Match standardization; Reference library">
- **Stage next:** <one stage name from START_HERE.md's table>

## Files on disk (exact paths)

| What | Path | Produced by |
|---|---|---|
| <input data> | <path> | user |
| <checkpoint> | <path>.rds | <script name>, step <n> |

## Site parameters already collected

- Latitude / longitude: <>
- Habitat: <>
- Marker: <>
- Target group: <>
- Other: <>

## Setup status

- Keys confirmed present: <list env var NAMES only>
- Still missing, needed by the next stage: <list, with fix text>

## Decisions made, so they are not re-opened

- <e.g. "Score-only consensus chosen over Bayesian: user has no time for a
  likelihood model">
- <e.g. "Wrapper path accepted; defaults unchanged">

## Open questions for the next stage

- <>
