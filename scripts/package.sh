#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
output_dir="$project_dir/dist"
app_path="$output_dir/OpenVale.app"
binary_path="$project_dir/.build/release/OpenVale"

cd "$project_dir"
print -u2 "Building OpenVale in release mode…"
swift build -c release >&2

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"

ditto "$binary_path" "$app_path/Contents/MacOS/OpenVale"
ditto "$project_dir/Packaging/Info.plist" "$app_path/Contents/Info.plist"
ditto "$project_dir/Packaging/OpenVale.icns" "$app_path/Contents/Resources/OpenVale.icns"

chmod +x "$app_path/Contents/MacOS/OpenVale"
codesign --force --deep --sign - "$app_path" >&2
codesign --verify --deep --strict "$app_path"
plutil -lint "$app_path/Contents/Info.plist" >/dev/null

print "$app_path"
