#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$1"
version="$(printf '%s' "$version" | sed 's/^v//')"
arch="$(dpkg --print-architecture)"
stage="build/pkg"
mkdir -p dist
rm -rf "$stage"
install -Dm755 build/numd "$stage/usr/bin/numd"
install -Dm644 config/numd.ini "$stage/etc/numd/config.ini"
install -Dm644 packaging/numd.service "$stage/usr/lib/systemd/system/numd.service"
mkdir -p "$stage/DEBIAN"
chmod 755 "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<CONTROL
Package: numd
Version: $version
Section: utils
Priority: optional
Architecture: $arch
Maintainer: cheeseonamonkey <noreply@github.com>
Depends: libc6 (>= 2.35)
Description: Configurable Num Lock modifier and numpad shortcut daemon
 A lightweight Nim evdev/uinput remapper that preserves ordinary numpad input
 and sends customizable keyboard shortcuts when Num Lock is held.
CONTROL
printf '/etc/numd/config.ini\n' > "$stage/DEBIAN/conffiles"
dpkg-deb --root-owner-group --build "$stage" "dist/numd_$version"_"$arch.deb"
