#!/bin/bash
# Build and sign the pinned Silo engine app embedded by build-app.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FJORD_APP="${1:?usage: build-silod.sh FJORD_APP SIGNING_IDENTITY}"
SIGNING_IDENTITY="${2:?usage: build-silod.sh FJORD_APP SIGNING_IDENTITY}"
SILO_REPO="${SILO_REPO_PATH:-$ROOT/../microsandbox-workspaces}"
SILO_COMMIT="$(tr -d '[:space:]' < "$ROOT/scripts/silod.commit")"
SILO_ROOT="$SILO_REPO/app/SiloUI"
SILOD_SOURCE="$SILO_ROOT/src-tauri/silod"
SILO_TARGET_DIR="${SILO_TARGET_DIR:-$ROOT/build/silod-target}"

if [ ! -d "$SILO_REPO/.git" ] && [ ! -f "$SILO_REPO/.git" ]; then
  echo "Silo checkout not found at $SILO_REPO (set SILO_REPO_PATH to its checkout)." >&2
  exit 1
fi
ACTUAL_COMMIT="$(git -C "$SILO_REPO" rev-parse HEAD)"
if [ "$ACTUAL_COMMIT" != "$SILO_COMMIT" ]; then
  echo "Silo checkout is $ACTUAL_COMMIT; scripts/silod.commit pins $SILO_COMMIT." >&2
  exit 1
fi
if [ -n "$(git -C "$SILO_REPO" status --porcelain --untracked-files=all -- app/SiloUI/Cargo.toml app/SiloUI/Cargo.lock app/SiloUI/api app/SiloUI/src-tauri/engine app/SiloUI/src-tauri/silod)" ]; then
  echo "The pinned Silo engine sources have local changes; use a clean checkout of $SILO_COMMIT." >&2
  exit 1
fi
for required in \
  "$SILO_ROOT/Cargo.toml" \
  "$SILO_ROOT/Cargo.lock" \
  "$SILOD_SOURCE"; do
  [ -e "$required" ] || { echo "Missing pinned Silo source: $required" >&2; exit 1; }
done

APP_CONTENTS="$FJORD_APP/Contents"
ENGINE_APP="$APP_CONTENTS/Resources/SiloEngineDistribution/Silo Engine.app"
ENGINE_CONTENTS="$ENGINE_APP/Contents"
ENGINE_RESOURCES="$ENGINE_CONTENTS/Resources"
ENGINE_EXECUTABLE="$ENGINE_CONTENTS/MacOS/silod"
AGENT_NAME="org.silo.preview.engine.plist"
SOURCE_PLIST="$SILOD_SOURCE/macos/LaunchAgents/$AGENT_NAME"
SOURCE_INFO="$SILOD_SOURCE/macos/Info.production.plist"
SOURCE_MANIFEST="$SILOD_SOURCE/macos/resources/engine-manifest.production.json"
SOURCE_BINARY="$ROOT/build/silod-bundle/silod"

for required in "$SOURCE_PLIST" "$SOURCE_INFO" "$SOURCE_MANIFEST"; do
  [ -f "$required" ] || { echo "Missing silod packaging input: $required" >&2; exit 1; }
done

CODE_REQUIREMENT="${SILOD_PRODUCTION_CODE_REQUIREMENT:-}"
if [ -z "$CODE_REQUIREMENT" ] && [ "$SIGNING_IDENTITY" != "-" ]; then
  CERT_HASH="$(security find-identity -p codesigning | awk -v identity="$SIGNING_IDENTITY" 'index($0, "\"" identity "\"") { print $2; exit }')"
  if [ -n "$CERT_HASH" ]; then
    CODE_REQUIREMENT="certificate leaf = H\"$CERT_HASH\""
  fi
fi
if [ -z "$CODE_REQUIREMENT" ]; then
  # Local ad-hoc builds still verify the signed bundle and its identifier. Release builds
  # inherit the Fjord signing certificate and pin its leaf certificate above.
  CODE_REQUIREMENT='identifier "org.silo.preview.engine"'
fi

build_silod() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    SILOD_PRODUCTION_CODE_REQUIREMENT="$CODE_REQUIREMENT" \
      CARGO_TARGET_DIR="$SILO_TARGET_DIR" \
      cargo +1.94.0 build --locked --release --manifest-path "$SILO_ROOT/Cargo.toml" -p silod
  else
    SILOD_PRODUCTION_CODE_REQUIREMENT="$CODE_REQUIREMENT" \
      CARGO_TARGET_DIR="$SILO_TARGET_DIR" \
      cargo +1.94.0 build --locked --release --manifest-path "$SILO_ROOT/Cargo.toml" -p silod --target "$target"
  fi
}

if [ "${UNIVERSAL:-0}" = "1" ]; then
  build_silod aarch64-apple-darwin
  build_silod x86_64-apple-darwin
  mkdir -p "$(dirname "$SOURCE_BINARY")"
  lipo -create \
    "$SILO_TARGET_DIR/aarch64-apple-darwin/release/silod" \
    "$SILO_TARGET_DIR/x86_64-apple-darwin/release/silod" \
    -output "$SOURCE_BINARY"
else
  build_silod
  mkdir -p "$(dirname "$SOURCE_BINARY")"
  cp "$SILO_TARGET_DIR/release/silod" "$SOURCE_BINARY"
fi
[ -x "$SOURCE_BINARY" ] || { echo "Cargo did not produce $SOURCE_BINARY" >&2; exit 1; }

rm -rf "$ENGINE_APP"
mkdir -p "$ENGINE_CONTENTS/MacOS" "$ENGINE_CONTENTS/Library/LaunchAgents" "$ENGINE_RESOURCES"
cp "$SOURCE_BINARY" "$ENGINE_EXECUTABLE"
cp "$SOURCE_INFO" "$ENGINE_CONTENTS/Info.plist"
cp "$SOURCE_PLIST" "$ENGINE_CONTENTS/Library/LaunchAgents/$AGENT_NAME"
python3 - "$SOURCE_MANIFEST" "$ENGINE_RESOURCES/engine-manifest.json" "$SILO_COMMIT" <<'PY'
import json
import sys

source, destination, commit = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    manifest = json.load(handle)
manifest["engineBuild"] = f"silo-{commit}"
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

# SMAppService resolves this plist from Fjord.app. The executable remains in the
# self-contained Silo Engine.app so silod sees its own bundle identifier and resources.
OUTER_AGENT="$APP_CONTENTS/Library/LaunchAgents/$AGENT_NAME"
mkdir -p "$(dirname "$OUTER_AGENT")"
cp "$SOURCE_PLIST" "$OUTER_AGENT"
plutil -replace BundleProgram -string \
  "Contents/Resources/SiloEngineDistribution/Silo Engine.app/Contents/MacOS/silod" \
  "$OUTER_AGENT"

# Sign nested code first. Do not use --deep: it would replace the engine's signature.
codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" \
  --entitlements "$ROOT/Resources/SiloEngineEntitlements.plist" "$ENGINE_APP"
codesign --verify --strict --verbose=2 "$ENGINE_APP"
codesign --display --entitlements :- "$ENGINE_EXECUTABLE" 2>&1 \
  | python3 -c 'import plistlib, sys; text = sys.stdin.read(); start = text.find("<?xml"); (start >= 0) or sys.exit("codesign returned no entitlement plist"); entitlements = plistlib.loads(text[start:].encode()); sys.exit(0 if entitlements.get("com.apple.security.virtualization") is True else 1)' \
  || { echo "silod is missing com.apple.security.virtualization" >&2; exit 1; }
plutil -lint "$OUTER_AGENT" "$ENGINE_CONTENTS/Library/LaunchAgents/$AGENT_NAME" >/dev/null

echo "Embedded silod from Silo $SILO_COMMIT in $ENGINE_APP"
