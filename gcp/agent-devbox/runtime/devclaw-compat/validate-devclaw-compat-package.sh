#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

EXPECTED_PACKAGE="@laurentenhoor/devclaw"
EXPECTED_VERSION="1.6.10"
EXPECTED_INTEGRITY="sha512-XSzsSi52hFZjj+y+Iww9P5s28NmCNQBvGOZzQRBUvbOzEJM+R4S+EcpdqxPzbFmS66X6KjMEqf3wSR/WeMFkdg=="
EXPECTED_PLUGIN_ID="devclaw"
EXPECTED_TOOL_COUNT="23"
COMPAT_REVISION="${DEVCLAW_COMPAT_REVISION:-aiops-1}"

fail() {
  printf '[validate-devclaw-compat-package] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  validate-devclaw-compat-package.sh --tarball FILE [--overlay FILE] [--build-manifest FILE]
USAGE
}

TARBALL=""
BUILD_MANIFEST=""
OVERLAY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/devclaw-manifest-overlay.json"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tarball)
      TARBALL="${2:-}"
      shift 2
      ;;
    --overlay)
      OVERLAY_FILE="${2:-}"
      shift 2
      ;;
    --build-manifest)
      BUILD_MANIFEST="${2:-}"
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

[[ -n "$TARBALL" ]] || fail "--tarball is required."
[[ -f "$TARBALL" ]] || fail "Missing tarball: $TARBALL"
[[ -f "$OVERLAY_FILE" ]] || fail "Missing overlay: $OVERLAY_FILE"

command -v npm >/dev/null 2>&1 || fail "Missing npm."
command -v node >/dev/null 2>&1 || fail "Missing node."
command -v jq >/dev/null 2>&1 || fail "Missing jq."
command -v tar >/dev/null 2>&1 || fail "Missing tar."
command -v sha256sum >/dev/null 2>&1 || fail "Missing sha256sum."

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PATCHED_SHA256="$(sha256sum "$TARBALL" | awk '{print $1}')"

if [[ -n "$BUILD_MANIFEST" ]]; then
  [[ -f "$BUILD_MANIFEST" ]] || fail "Missing build manifest: $BUILD_MANIFEST"
  [[ "$(jq -r '.compatRevision' "$BUILD_MANIFEST")" == "$COMPAT_REVISION" ]] ||
    fail "build manifest compatibility revision mismatch."
  [[ "$(jq -r '.patchedTarballSha256' "$BUILD_MANIFEST")" == "$PATCHED_SHA256" ]] ||
    fail "build manifest patched tarball SHA-256 mismatch."
fi

npm view "${EXPECTED_PACKAGE}@${EXPECTED_VERSION}" \
  name version dist.integrity dist.shasum dist.tarball peerDependencies engines \
  --json > "$WORK_DIR/upstream-npm-view.json"

node - "$WORK_DIR/upstream-npm-view.json" "$EXPECTED_PACKAGE" "$EXPECTED_VERSION" "$EXPECTED_INTEGRITY" <<'NODE'
const fs = require("fs");
const [file, expectedName, expectedVersion, expectedIntegrity] = process.argv.slice(2);
const metadata = JSON.parse(fs.readFileSync(file, "utf8"));
const get = (key) => metadata[key] ?? key.split(".").reduce((current, part) => current && current[part], metadata);
if (metadata.name !== expectedName) throw new Error(`name mismatch: ${metadata.name}`);
if (metadata.version !== expectedVersion) throw new Error(`version mismatch: ${metadata.version}`);
if (get("dist.integrity") !== expectedIntegrity) throw new Error(`integrity mismatch: ${get("dist.integrity")}`);
NODE

npm pack "${EXPECTED_PACKAGE}@${EXPECTED_VERSION}" --pack-destination "$WORK_DIR" > "$WORK_DIR/npm-pack.out"
UPSTREAM_TARBALL="$WORK_DIR/$(tail -n1 "$WORK_DIR/npm-pack.out")"
[[ -f "$UPSTREAM_TARBALL" ]] || fail "failed to fetch upstream tarball."

mkdir "$WORK_DIR/upstream" "$WORK_DIR/patched"
tar -xzf "$UPSTREAM_TARBALL" -C "$WORK_DIR/upstream"
tar -xzf "$TARBALL" -C "$WORK_DIR/patched"

PACKAGE_JSON="$WORK_DIR/patched/package/package.json"
PLUGIN_JSON="$WORK_DIR/patched/package/openclaw.plugin.json"

[[ "$(jq -r '.name' "$PACKAGE_JSON")" == "$EXPECTED_PACKAGE" ]] ||
  fail "package name mismatch."
[[ "$(jq -r '.version' "$PACKAGE_JSON")" == "$EXPECTED_VERSION" ]] ||
  fail "package version mismatch."
[[ "$(jq -r '.id' "$PLUGIN_JSON")" == "$EXPECTED_PLUGIN_ID" ]] ||
  fail "plugin id mismatch."

node - "$PLUGIN_JSON" "$OVERLAY_FILE" "$EXPECTED_TOOL_COUNT" <<'NODE'
const fs = require("fs");
const [manifestFile, overlayFile, expectedCount] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
const overlay = JSON.parse(fs.readFileSync(overlayFile, "utf8"));
if (manifest.activation?.onStartup !== true) throw new Error("activation.onStartup must be true");
const tools = manifest.contracts?.tools;
if (!Array.isArray(tools)) throw new Error("contracts.tools must be an array");
if (tools.length !== Number(expectedCount)) throw new Error(`expected ${expectedCount} tools, found ${tools.length}`);
if (new Set(tools).size !== tools.length) throw new Error("contracts.tools contains duplicate names");
if (JSON.stringify(tools) !== JSON.stringify(overlay.contracts.tools)) {
  throw new Error("contracts.tools does not match reviewed overlay");
}
NODE

(
  cd "$WORK_DIR/upstream/package"
  find . -type f -print | sort
) > "$WORK_DIR/upstream-files.txt"
(
  cd "$WORK_DIR/patched/package"
  find . -type f -print | sort
) > "$WORK_DIR/patched-files.txt"
diff -u "$WORK_DIR/upstream-files.txt" "$WORK_DIR/patched-files.txt" >/dev/null ||
  fail "patched package file list differs from upstream."

while IFS= read -r relative_path; do
  relative_path="${relative_path#./}"
  if [[ "$relative_path" == "openclaw.plugin.json" ]]; then
    continue
  fi
  upstream_hash="$(sha256sum "$WORK_DIR/upstream/package/$relative_path" | awk '{print $1}')"
  patched_hash="$(sha256sum "$WORK_DIR/patched/package/$relative_path" | awk '{print $1}')"
  [[ "$upstream_hash" == "$patched_hash" ]] ||
    fail "unexpected source/package modification: $relative_path"
done < "$WORK_DIR/upstream-files.txt"

if find "$WORK_DIR/patched/package" -path '*/node_modules/*' -o -path '*/.git/*' -o -path '*/.openclaw/*' -o -path '*/workspace/*' | grep -q .; then
  fail "patched package contains bundled runtime, repo, or dependency state."
fi

if grep -R -I -E 'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY|gho_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}' "$WORK_DIR/patched/package" >/dev/null; then
  fail "patched package appears to contain credential material."
fi

printf '[validate-devclaw-compat-package] Package validated: %s sha256=%s compat_revision=%s\n' \
  "$TARBALL" "$PATCHED_SHA256" "$COMPAT_REVISION"
