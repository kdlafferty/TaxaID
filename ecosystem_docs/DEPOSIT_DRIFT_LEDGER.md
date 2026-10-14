# Deposit drift ledger

**Why this file exists.** The maintainer's standing policy, 2026-10-14: *"I am OK
with changes that affect Dryad, but we are going to wait to update changes at
Dryad."* Code changes freely; the deposit refresh is batched and deferred. That
decouples two things that used to move together, and it creates a hazard with no
other owner -- by the time someone refreshes Dryad, nobody will remember which
deposited columns drifted, by how much, or why. This ledger is that record.

**The live deposit.** `r2`, built from tree `dafe7a2`, tag
`calintertidal-r2-2026-10-13`, deposited as
`reporting/out/r2/dryad_2026-10-13/`. **20 CSVs, no `.rds`** -- verified, so a
column that lives only in an `.rds` is NOT deposited. Anything citing a tree for
r2 cites `dafe7a2`, never `main` and never `1.0.0`.

**Rules.**
1. One row per change on `main` (or in the eDNA reporting layer) that would make
   a regenerated deposit differ from the published one. A change that cannot
   alter any deposited CSV does not belong here -- say so in the row below and
   give the evidence, rather than leaving it ambiguous.
2. Quantify the drift when it lands, not at refresh time. The measurement is
   cheap while the context is fresh and expensive to reconstruct later.
3. Name the deposited FILE and COLUMN, not just the function.
4. The deposit itself is never edited in place. `r2` stays as published until a
   batched refresh replaces it wholesale.

---

## Open drift -- in `main`, NOT in the deposit

### 1. Deterministic candidate tie ordering (`e3b03e3`, + eDNA `7fe9176`)

| | |
|---|---|
| **What** | `posterior_consensus()` breaks candidate ties on `taxon_name`, and provenance ties on `hypothesis_type`, by BYTE order (`method = "radix"`). The reporting layer (`archive_csv.R`) carries the same key. |
| **Deposited file** | `ESV_site_calls.csv` |
| **Columns** | `plausible_top` (cols 10), `consensus_hypothesis_type` (col 20) |
| **Drift, measured on r2's own consensus object** | `plausible_top` strings that reorder: **437 of 49,466 (0.88%)**. Of those, the QUOTED LEADING taxon changes: **5 (0.01%)**. `n_plausible` and `n_plausible_not_shown` are counts, not orders -- **unchanged**. |
| **Calls** | **No call changes.** Where two species tie, the consensus already backs off to their LCA. What was arbitrary was only which equal got presented first. |
| **Why it was worth doing anyway** | A deposited column presented one of several equally-supported taxa as "the top" with nothing in the data deciding which. Under the old code the answer also depended on the machine's locale. |

### Not drift, recorded so it is not re-investigated

- **`set.seed(42L)` at `compute_posterior()` (eDNA `003b973`).** Pins
  `consensus_confidence_score`. **Verified twice** that column appears in NO
  deposited CSV (`consensus_final_esv_site.rds` is not part of the deposit) and
  in no report table. Reproducibility hygiene; zero deposit drift.
- **`review_assignments()` geography combination (`983324c`).** CalIntertidal
  does not run `review_assignments()` at all -- it is a commented-out `## STUB`
  at workflow line 4309 -- and every live caller elsewhere hand-writes
  `geography`, so their prompts are byte-identical. Zero deposit drift.
- **The restore-imputation ceiling (`b56a85a`).** Predates r2; already in the
  deposited tree. Not drift.

---

## At refresh time

1. Re-read this ledger top to bottom and re-measure each open row against the
   tree being deposited -- a figure measured against r2 is evidence about r2,
   not about whatever tree comes next.
2. Regenerate from ONE tree, tag it, and cite that tag.
3. Move every row landed in that refresh into a "Shipped in <tag>" section with
   its final measured numbers. Do not delete rows; the history is the point.
4. The correction email is the maintainer's to send, as it was for r2.
