#!/bin/bash
# Dead-call sweep for the production workflow scripts.
#
# Collects every function name defined under any Taxa*/archive_*/ directory,
# subtracts anything still exported by a live package, and reports calls to what
# remains -- on non-comment lines only.
#
# WHY THIS EXISTS: the 2026-09-15 structural audit validated `Pkg::fun()` calls
# against NAMESPACE but resolved BARE calls only positively, against the live
# export list, so a bare call to an archived function simply vanished from its
# outline instead of being flagged. That is how the canonical template's dead
# Section 5 (the archived GLMM chain, called bare) passed an audit that caught
# the retired TEST template's identical defect (called namespaced).
#
# Usage:  bash check_dead_calls.sh /path/to/workflow.R [more.R ...]
# Run from the TaxaID repository root.
set -euo pipefail
TMP=$(mktemp -d)
grep -rhoE '^[A-Za-z_.][A-Za-z0-9_.]* *<- *function' --include=*.R Taxa*/archive_*/ 2>/dev/null \
  | sed -E 's/ *<- *function//' | sort -u > "$TMP/archived.txt"
for d in Taxa*; do [ -f "$d/NAMESPACE" ] && grep -h '^export(' "$d/NAMESPACE"; done \
  | sed -E 's/^export\((.*)\)$/\1/' | tr -d '"' | sort -u > "$TMP/live.txt"
comm -23 "$TMP/archived.txt" "$TMP/live.txt" > "$TMP/dead.txt"
echo "archived-and-not-re-exported function names: $(wc -l < "$TMP/dead.txt" | tr -d ' ')"
PAT="(^|[^A-Za-z0-9_.:])($(paste -sd'|' "$TMP/dead.txt"))\s*\("
for f in "$@"; do
  echo "######## $(basename "$f")"
  hits=$(grep -nE "$PAT" "$f" 2>/dev/null | grep -vE '^\s*[0-9]+:\s*#' || true)
  if [ -z "$hits" ]; then echo "  clean"; else echo "$hits" | cut -c1-120; fi
done
rm -rf "$TMP"
