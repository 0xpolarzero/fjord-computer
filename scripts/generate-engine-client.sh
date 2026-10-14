#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_dir="$repo_root/tools/silo-swift"
mode="${1:---check}"
if [[ "$mode" != "--check" && "$mode" != "--write" ]]; then
  echo "Usage: scripts/generate-engine-client.sh [--check|--write]" >&2
  exit 2
fi

temporary_dir="$(mktemp -d /private/tmp/fjord-silo-swift.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
tool_work_dir="$temporary_dir/tool"
mkdir -p "$tool_work_dir"
cp "$tool_dir/package.json" "$tool_dir/package-lock.json" "$tool_dir/generate.mjs" \
  "$tool_dir/swift-renderer.mjs" "$tool_dir/generator-transforms.mjs" "$tool_work_dir/"

(
  cd "$tool_work_dir"
  npm_config_cache=/private/tmp/fjord-silo-swift-npm-cache npm ci --ignore-scripts --no-audit --no-fund
  node generate.mjs \
    "$repo_root/schemas/silo-api/schema.json" \
    "$temporary_dir/SiloAPI.swift" \
    "$temporary_dir/SiloMethods.swift"
)

if [[ "$mode" == "--write" ]]; then
  cp "$temporary_dir/SiloAPI.swift" "$repo_root/Sources/Fjord/Generated/SiloAPI.swift"
  cp "$temporary_dir/SiloMethods.swift" "$repo_root/Sources/Fjord/Generated/SiloMethods.swift"
  echo "Regenerated Sources/Fjord/Generated/SiloAPI.swift and SiloMethods.swift."
  exit 0
fi

diff -u "$repo_root/Sources/Fjord/Generated/SiloAPI.swift" "$temporary_dir/SiloAPI.swift"
diff -u "$repo_root/Sources/Fjord/Generated/SiloMethods.swift" "$temporary_dir/SiloMethods.swift"
echo "Generated Silo client matches the checked-in schema."
