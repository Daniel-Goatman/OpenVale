#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
install_dir="$HOME/Applications"
install_path="$install_dir/OpenVale.app"
should_launch=true

if [[ ${1:-} == "--no-launch" ]]; then
    should_launch=false
elif [[ $# -gt 0 ]]; then
    print -u2 "Usage: ./scripts/install.sh [--no-launch]"
    exit 2
fi

macos_version=$(sw_vers -productVersion)
macos_major=${macos_version%%.*}
if (( macos_major < 13 )); then
    print -u2 "OpenVale requires macOS 13 Ventura or later. This Mac is running macOS $macos_version."
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    print -u2 "Swift is missing. Install Apple Command Line Tools with: xcode-select --install"
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    print -u2 "Apple Command Line Tools are not configured. Run: xcode-select --install"
    exit 1
fi

print "Building OpenVale for this Mac ($macos_version, $(uname -m))…"
built_app=$("$script_dir/package.sh")

mkdir -p "$install_dir"
if pgrep -x OpenVale >/dev/null 2>&1; then
    print "Closing the currently running OpenVale…"
    pkill -x OpenVale
    for _ in {1..20}; do
        pgrep -x OpenVale >/dev/null 2>&1 || break
        sleep 0.1
    done
fi

print "Installing OpenVale in $install_dir…"
rm -rf "$install_path"
ditto "$built_app" "$install_path"
codesign --verify --deep --strict "$install_path"

if $should_launch; then
    print "Launching OpenVale…"
    open "$install_path"
fi

print "Installed: $install_path"
print "Wallpapers: $HOME/Library/Application Support/OpenVale/Wallpapers"
