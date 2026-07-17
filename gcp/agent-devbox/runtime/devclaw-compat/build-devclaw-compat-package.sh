#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

EXPECTED_PACKAGE="@laurentenhoor/devclaw"
EXPECTED_VERSION="1.6.10"
EXPECTED_INTEGRITY="sha512-XSzsSi52hFZjj+y+Iww9P5s28NmCNQBvGOZzQRBUvbOzEJM+R4S+EcpdqxPzbFmS66X6KjMEqf3wSR/WeMFkdg=="
EXPECTED_PLUGIN_ID="devclaw"
EXPECTED_TOOL_COUNT="23"
EXPECTED_JSON_RESULT_IMPORT_COUNT="23"
COMPAT_REVISION="${DEVCLAW_COMPAT_REVISION:-aiops-1}"

fail() {
  printf '[build-devclaw-compat-package] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[build-devclaw-compat-package] %s\n' "$*"
}

usage() {
  cat <<'USAGE'
Usage:
  build-devclaw-compat-package.sh --output-dir DIR [--upstream-tarball FILE] [--overlay FILE]

Builds a local npm-pack tarball for @laurentenhoor/devclaw@1.6.10 with the
reviewed OpenClaw 2026.7.1 manifest compatibility overlay.
USAGE
}

OUTPUT_DIR=""
UPSTREAM_TARBALL=""
OVERLAY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/devclaw-manifest-overlay.json"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --upstream-tarball)
      UPSTREAM_TARBALL="${2:-}"
      shift 2
      ;;
    --overlay)
      OVERLAY_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$OUTPUT_DIR" ]] || fail "--output-dir is required."
[[ -f "$OVERLAY_FILE" ]] || fail "Missing overlay file: $OVERLAY_FILE"

command -v npm >/dev/null 2>&1 || fail "Missing npm."
command -v node >/dev/null 2>&1 || fail "Missing node."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v tar >/dev/null 2>&1 || fail "Missing tar."
command -v sha256sum >/dev/null 2>&1 || fail "Missing sha256sum."

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
case "$OUTPUT_DIR" in
  *"/gcp/agent-devbox"*) fail "Output directory must be ignored and outside tracked source." ;;
esac

WORK_DIR="$(mktemp -d "$OUTPUT_DIR/devclaw-compat-build.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

NPM_VIEW="$OUTPUT_DIR/upstream-npm-view.json"
log "Verifying upstream npm metadata"
npm view "${EXPECTED_PACKAGE}@${EXPECTED_VERSION}" \
  name version dist.integrity dist.shasum dist.tarball peerDependencies engines \
  --json > "$NPM_VIEW"

node - "$NPM_VIEW" "$EXPECTED_PACKAGE" "$EXPECTED_VERSION" "$EXPECTED_INTEGRITY" <<'NODE'
const fs = require("fs");
const [file, expectedName, expectedVersion, expectedIntegrity] = process.argv.slice(2);
const metadata = JSON.parse(fs.readFileSync(file, "utf8"));
function value(key) {
  return metadata[key] ?? key.split(".").reduce((current, part) => current && current[part], metadata);
}
if (metadata.name !== expectedName) throw new Error(`name mismatch: ${metadata.name}`);
if (metadata.version !== expectedVersion) throw new Error(`version mismatch: ${metadata.version}`);
if (value("dist.integrity") !== expectedIntegrity) throw new Error(`integrity mismatch: ${value("dist.integrity")}`);
if (!String(value("dist.tarball") || "").startsWith("https://registry.npmjs.org/")) {
  throw new Error(`unexpected tarball URL: ${value("dist.tarball")}`);
}
NODE

if [[ -n "$UPSTREAM_TARBALL" ]]; then
  [[ -f "$UPSTREAM_TARBALL" ]] || fail "Missing upstream tarball: $UPSTREAM_TARBALL"
  cp "$UPSTREAM_TARBALL" "$WORK_DIR/upstream.tgz"
else
  log "Fetching exact upstream npm artifact"
  npm pack "${EXPECTED_PACKAGE}@${EXPECTED_VERSION}" --pack-destination "$WORK_DIR" > "$WORK_DIR/npm-pack.out"
  PACKED_NAME="$(tail -n1 "$WORK_DIR/npm-pack.out")"
  [[ -n "$PACKED_NAME" ]] || fail "npm pack did not report a tarball name."
  mv "$WORK_DIR/$PACKED_NAME" "$WORK_DIR/upstream.tgz"
fi

UPSTREAM_SHA256="$(sha256sum "$WORK_DIR/upstream.tgz" | awk '{print $1}')"
log "Upstream tarball SHA-256: $UPSTREAM_SHA256"

mkdir "$WORK_DIR/original" "$WORK_DIR/patched"
tar -xzf "$WORK_DIR/upstream.tgz" -C "$WORK_DIR/original"
cp -a "$WORK_DIR/original/package" "$WORK_DIR/patched/package"

PACKAGE_JSON="$WORK_DIR/patched/package/package.json"
PLUGIN_JSON="$WORK_DIR/patched/package/openclaw.plugin.json"
ORIGINAL_PLUGIN_JSON="$WORK_DIR/original/package/openclaw.plugin.json"

[[ "$(jq -r '.name' "$PACKAGE_JSON")" == "$EXPECTED_PACKAGE" ]] ||
  fail "package name changed."
[[ "$(jq -r '.version' "$PACKAGE_JSON")" == "$EXPECTED_VERSION" ]] ||
  fail "package version changed."
[[ "$(jq -r '.id' "$ORIGINAL_PLUGIN_JSON")" == "$EXPECTED_PLUGIN_ID" ]] ||
  fail "unexpected original plugin id."
[[ "$(jq -r 'has("contracts")' "$ORIGINAL_PLUGIN_JSON")" == "false" ]] ||
  fail "upstream manifest unexpectedly already contains contracts."
[[ "$(jq -r 'has("activation")' "$ORIGINAL_PLUGIN_JSON")" == "false" ]] ||
  fail "upstream manifest unexpectedly already contains activation."

log "Applying reviewed manifest overlay"
jq -s '.[0] * .[1]' "$ORIGINAL_PLUGIN_JSON" "$OVERLAY_FILE" > "$PLUGIN_JSON.tmp"
mv "$PLUGIN_JSON.tmp" "$PLUGIN_JSON"

log "Applying OpenClaw 2026.7.1 tool-result compatibility shim"
node - "$WORK_DIR/patched/package/dist/index.js" "$EXPECTED_JSON_RESULT_IMPORT_COUNT" <<'NODE'
const fs = require("fs");
const [indexFile, expectedImportCount] = process.argv.slice(2);
let source = fs.readFileSync(indexFile, "utf8");
const importPattern = /^import\s+\{\s*jsonResult(?:\s+as\s+(jsonResult\d+))?\s*\}\s+from\s+["']openclaw\/plugin-sdk["'];\r?\n?/gm;
const aliases = [];
source = source.replace(importPattern, (_match, alias) => {
  const name = alias || "jsonResult";
  aliases.push(name);
  return `const ${name} = __devclawAiopsJsonResult;\n`;
});
if (aliases.length !== Number(expectedImportCount)) {
  throw new Error(`expected ${expectedImportCount} jsonResult imports, found ${aliases.length}`);
}
if (new Set(aliases).size !== aliases.length) {
  throw new Error("duplicate jsonResult compatibility aliases found");
}
if (/import\s+\{\s*jsonResult(?:\s+as\s+jsonResult\d+)?\s*\}\s+from\s+["']openclaw\/plugin-sdk["'];/.test(source)) {
  throw new Error("unpatched jsonResult import remains");
}
const helper = `\n// aiops-1 compatibility shim: OpenClaw 2026.7.1 does not export jsonResult from openclaw/plugin-sdk.\nfunction __devclawAiopsJsonResult(payload) {\n  return {\n    content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],\n    details: payload\n  };\n}\n\n`;
const firstAlias = `const ${aliases[0]} = __devclawAiopsJsonResult;\n`;
source = source.replace(firstAlias, `${helper}${firstAlias}`);
for (const alias of aliases) {
  const aliasPattern = new RegExp(`\\b${alias}\\s*\\(`);
  if (!aliasPattern.test(source)) {
    throw new Error(`jsonResult alias is not used after compatibility patch: ${alias}`);
  }
}
fs.writeFileSync(indexFile, source);
console.log(JSON.stringify({ jsonResultImportCount: aliases.length, aliases }));
NODE

node - "$PLUGIN_JSON" "$OVERLAY_FILE" "$EXPECTED_PLUGIN_ID" "$EXPECTED_TOOL_COUNT" <<'NODE'
const fs = require("fs");
const [manifestFile, overlayFile, expectedId, expectedCount] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
const overlay = JSON.parse(fs.readFileSync(overlayFile, "utf8"));
if (manifest.id !== expectedId) throw new Error(`manifest id mismatch: ${manifest.id}`);
if (manifest.activation?.onStartup !== true) throw new Error("activation.onStartup must be true");
const tools = manifest.contracts?.tools;
if (!Array.isArray(tools)) throw new Error("contracts.tools must be an array");
const unique = new Set(tools);
if (tools.length !== Number(expectedCount)) throw new Error(`expected ${expectedCount} tools, found ${tools.length}`);
if (unique.size !== tools.length) throw new Error("contracts.tools contains duplicate names");
if (JSON.stringify(tools) !== JSON.stringify(overlay.contracts.tools)) {
  throw new Error("contracts.tools does not match reviewed overlay order/content");
}
NODE

log "Verifying only reviewed compatibility files changed"
(
  cd "$WORK_DIR/original/package"
  find . -type f -print | sort
) > "$WORK_DIR/original-files.txt"
(
  cd "$WORK_DIR/patched/package"
  find . -type f -print | sort
) > "$WORK_DIR/patched-files.txt"
diff -u "$WORK_DIR/original-files.txt" "$WORK_DIR/patched-files.txt" >/dev/null ||
  fail "patched package file list differs from upstream."

while IFS= read -r relative_path; do
  relative_path="${relative_path#./}"
  if [[ "$relative_path" == "openclaw.plugin.json" || "$relative_path" == "dist/index.js" ]]; then
    continue
  fi
  original_hash="$(sha256sum "$WORK_DIR/original/package/$relative_path" | awk '{print $1}')"
  patched_hash="$(sha256sum "$WORK_DIR/patched/package/$relative_path" | awk '{print $1}')"
  [[ "$original_hash" == "$patched_hash" ]] ||
    fail "unexpected source/package modification: $relative_path"
done < "$WORK_DIR/original-files.txt"

node - "$WORK_DIR/patched/package/dist/index.js" "$EXPECTED_JSON_RESULT_IMPORT_COUNT" <<'NODE'
const fs = require("fs");
const [indexFile, expectedImportCount] = process.argv.slice(2);
const source = fs.readFileSync(indexFile, "utf8");
if (!source.includes("function __devclawAiopsJsonResult(payload)")) {
  throw new Error("missing aiops-1 jsonResult compatibility shim");
}
if (/import\s+\{\s*jsonResult(?:\s+as\s+jsonResult\d+)?\s*\}\s+from\s+["']openclaw\/plugin-sdk["'];/.test(source)) {
  throw new Error("unavailable openclaw/plugin-sdk jsonResult import remains");
}
const aliases = Array.from(source.matchAll(/\bconst\s+(jsonResult\d*)\s*=\s*__devclawAiopsJsonResult;/g), (match) => match[1]);
if (aliases.length !== Number(expectedImportCount)) {
  throw new Error(`expected ${expectedImportCount} jsonResult aliases, found ${aliases.length}`);
}
if (new Set(aliases).size !== aliases.length) {
  throw new Error("duplicate jsonResult compatibility aliases found");
}
NODE

BUILD_CHECK_STATUS="not_available"
BUILD_CHECK_OUTPUT="$OUTPUT_DIR/openclaw-plugins-build-check.txt"
if command -v openclaw >/dev/null 2>&1; then
  set +e
  openclaw plugins build --root "$WORK_DIR/patched/package" --entry ./dist/index.js --check >"$BUILD_CHECK_OUTPUT" 2>&1
  build_check_rc=$?
  set -e
  if [[ "$build_check_rc" -eq 0 ]]; then
    BUILD_CHECK_STATUS="passed"
  elif grep -q 'does not expose defineToolPlugin metadata' "$BUILD_CHECK_OUTPUT"; then
    BUILD_CHECK_STATUS="legacy_dynamic_plugin_shape"
  else
    cat "$BUILD_CHECK_OUTPUT" >&2
    fail "OpenClaw plugin build check failed unexpectedly."
  fi
fi

log "Packing patched package"
PACK_DIR="$OUTPUT_DIR/pack"
rm -rf "$PACK_DIR"
mkdir -p "$PACK_DIR"
npm pack "$WORK_DIR/patched/package" --pack-destination "$PACK_DIR" > "$WORK_DIR/patched-pack.out"
PATCHED_NAME="$(tail -n1 "$WORK_DIR/patched-pack.out")"
[[ -f "$PACK_DIR/$PATCHED_NAME" ]] || fail "patched npm pack did not create expected tarball."
PATCHED_TARBALL="$OUTPUT_DIR/${PATCHED_NAME%.tgz}-${COMPAT_REVISION}.tgz"
mv "$PACK_DIR/$PATCHED_NAME" "$PATCHED_TARBALL"
rmdir "$PACK_DIR"
PATCHED_SHA256="$(sha256sum "$PATCHED_TARBALL" | awk '{print $1}')"

BUILD_MANIFEST="$OUTPUT_DIR/devclaw-compat-build-manifest.json"
jq -n \
  --arg packageName "$EXPECTED_PACKAGE" \
  --arg packageVersion "$EXPECTED_VERSION" \
  --arg compatRevision "$COMPAT_REVISION" \
  --arg npmIntegrity "$EXPECTED_INTEGRITY" \
  --arg upstreamSha256 "$UPSTREAM_SHA256" \
  --arg patchedTarball "$PATCHED_TARBALL" \
  --arg patchedSha256 "$PATCHED_SHA256" \
  --arg buildCheckStatus "$BUILD_CHECK_STATUS" \
  --argjson toolCount "$EXPECTED_TOOL_COUNT" \
  --argjson jsonResultImportCount "$EXPECTED_JSON_RESULT_IMPORT_COUNT" \
  '{
    packageName: $packageName,
    packageVersion: $packageVersion,
    compatRevision: $compatRevision,
    npmIntegrity: $npmIntegrity,
    upstreamTarballSha256: $upstreamSha256,
    patchedTarball: $patchedTarball,
    patchedTarballSha256: $patchedSha256,
    toolCount: $toolCount,
    jsonResultImportCount: $jsonResultImportCount,
    openclawPluginsBuildCheck: $buildCheckStatus
  }' > "$BUILD_MANIFEST"

log "Patched tarball: $PATCHED_TARBALL"
log "Patched tarball SHA-256: $PATCHED_SHA256"
log "Build manifest: $BUILD_MANIFEST"
