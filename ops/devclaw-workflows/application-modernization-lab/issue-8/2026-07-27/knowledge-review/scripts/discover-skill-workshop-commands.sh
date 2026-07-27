#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/devclaw-svc/.openclaw}"

echo "== npm projects =="
find "$OPENCLAW_HOME/npm/projects" -maxdepth 4 -type f -name package.json 2>/dev/null | sort || true

echo "== matching implementation lines =="
search_roots=(
  "/opt/devclaw/runtime/npm/lib/node_modules/openclaw/dist"
  "/opt/devclaw/runtime/npm/node_modules/openclaw/dist"
  "/opt/devclaw/runtime/npm/node_modules/@openclaw"
  "$OPENCLAW_HOME/npm/projects/laurentenhoor-devclaw-44c274b0c8__openclaw-generation__g-5e86cdd85d606dcb/node_modules/@laurentenhoor/devclaw/dist"
  "$OPENCLAW_HOME/npm/projects/openclaw-codex-8902d781d4/node_modules/@openclaw/codex/dist"
)
for root in "${search_roots[@]}"; do
  [[ -d "$root" ]] || continue
  echo "-- $root --"
  find "$root" -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) ! -name "*.map" -print0 \
    | xargs -0 grep -InE \
      "applyProposal|apply proposal|Skill Workshop|skill_workshop|skill-workshop|proposals.json|status.*applied|apply.*skill|workshop|proposal" \
    2>/dev/null \
    | sed -n '1,160p' \
    || true
done

echo "== command help probes =="
for bin in openclaw devclaw; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "-- $bin --"
    "$bin" --help 2>&1 | sed -n '1,80p'
  fi
done
