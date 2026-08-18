#!/bin/zsh

set -euo pipefail

install_path="$HOME/Applications/OpenVale.app"

if [[ -x "$install_path/Contents/MacOS/OpenVale" ]]; then
    "$install_path/Contents/MacOS/OpenVale" --unregister-login-item || true
fi

pkill -x OpenVale 2>/dev/null || true
rm -rf "$install_path"

print "Removed OpenVale.app."
print "Your wallpapers were kept in: $HOME/Library/Application Support/OpenVale/Wallpapers"
print "Delete that folder manually only if you also want to remove your videos."
