#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$project_root/Packaging/Info.plist"
package_json="$project_root/VSCodeExtension/package.json"
vsix_manifest="$project_root/Packaging/vsix/extension.vsixmanifest"
icon_source="$project_root/Assets/TickTimeAppIcon-1024.png"

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
extension_version="$(node -p 'require(process.argv[1]).version' "$package_json")"
manifest_version="$(sed -n 's/.*<Identity[^>]*Version="\([^"]*\)".*/\1/p' "$vsix_manifest")"

if [[ "$app_version" != "$extension_version" || "$app_version" != "$manifest_version" ]]; then
    printf 'Version mismatch: app=%s package=%s manifest=%s\n' \
        "$app_version" "$extension_version" "$manifest_version" >&2
    exit 1
fi

if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    printf 'Unsupported release version: %s\n' "$app_version" >&2
    exit 1
fi

if [[ ! -f "$icon_source" ]]; then
    printf 'App icon source not found: %s\n' "$icon_source" >&2
    exit 1
fi

release_root="$project_root/Releases"
output_dir="$release_root/$app_version"
staging_dir="$(mktemp -d /private/tmp/TickTime-package.XXXXXX)"
trap 'rm -rf -- "$staging_dir"' EXIT

artifact_dir="$staging_dir/release"
mkdir -p "$artifact_dir"

CLANG_MODULE_CACHE_PATH="$project_root/.cache/clang" \
swift build \
    --package-path "$project_root" \
    -c release \
    --disable-sandbox \
    --cache-path "$project_root/.cache/swiftpm"

app_bundle="$staging_dir/TickTime.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_root/.build/release/TickTime" "$app_bundle/Contents/MacOS/TickTime"
cp "$info_plist" "$app_bundle/Contents/Info.plist"

node "$project_root/Packaging/create-icns.js" \
    "$icon_source" \
    "$app_bundle/Contents/Resources/TickTime.icns"

codesign --force --deep --sign - "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

ditto "$app_bundle" "$artifact_dir/TickTime.app"
ditto -c -k --sequesterRsrc --keepParent \
    "$artifact_dir/TickTime.app" \
    "$artifact_dir/TickTime-macOS.zip"

vsix_root="$staging_dir/vsix"
mkdir -p "$vsix_root/extension"
cp "$project_root/Packaging/vsix/[Content_Types].xml" "$vsix_root/"
cp "$project_root/Packaging/vsix/extension.vsixmanifest" "$vsix_root/"
cp \
    "$package_json" \
    "$project_root/VSCodeExtension/extension.js" \
    "$project_root/VSCodeExtension/heartbeat-core.js" \
    "$project_root/VSCodeExtension/icon.png" \
    "$project_root/VSCodeExtension/README.md" \
    "$project_root/LICENSE" \
    "$vsix_root/extension/"

(
    cd "$vsix_root"
    zip -q -FS -r "$artifact_dir/TickTime-vscode-$app_version.vsix" \
        '[Content_Types].xml' extension.vsixmanifest extension
)
unzip -t "$artifact_dir/TickTime-vscode-$app_version.vsix"

source_root="$staging_dir/TickTime"
while IFS= read -r -d '' source_path; do
    source_destination="$source_root/$source_path"
    mkdir -p "$(dirname "$source_destination")"
    cp -p "$project_root/$source_path" "$source_destination"
done < <(git -C "$project_root" ls-files --cached --others --exclude-standard -z)
ditto -c -k --sequesterRsrc --keepParent \
    "$source_root" \
    "$artifact_dir/TickTime-source.zip"

"$project_root/Packaging/smoke-test.sh" "$artifact_dir/TickTime.app"

mkdir -p "$release_root"
rm -rf -- "$output_dir"
mv "$artifact_dir" "$output_dir"

printf 'Release artifacts generated in %s\n' "$output_dir"
