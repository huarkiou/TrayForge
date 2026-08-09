#!/usr/bin/env bash
# Build a release bundle and package it as an Arch Linux pacman package.
#
# Reproducible one-shot flow:
#   1. flutter build linux --release
#   2. stage the PKGBUILD, bundle and icon into build/arch/ (makepkg work dir)
#   3. sync pkgver from pubspec.yaml into the staged PKGBUILD
#   4. makepkg (checks gtk3 / libayatana-appindicator are installed)
#   5. clean every intermediate artifact, keep only the .pkg.tar.zst
#
# Everything (bundle, work dir, package) lives under build/, so the repo
# stays clean: packaging/arch/ holds only the source files.
#
# Usage: scripts/package-arch.sh
# Output: build/arch/trayforge-<ver>-<rel>-x86_64.pkg.tar.zst
# Install with: sudo pacman -U build/arch/trayforge-*.pkg.tar.zst
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SRC_DIR="$ROOT/packaging/arch"
WORK_DIR="$ROOT/build/arch"
PKGBUILD="$SRC_DIR/PKGBUILD"

# ---- Locate flutter: PATH first, then the standard user install location.
if ! command -v flutter >/dev/null 2>&1 && [ -x "$HOME/flutter/bin/flutter" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH or \$HOME/flutter" >&2
  exit 1
fi

# ---- Sync pkgver from pubspec.yaml so version bumps flow through.
pubspec_ver="$(sed -n 's/^version: \([0-9][0-9.]*\)[+ ].*$/\1/p' pubspec.yaml | head -1)"
if [ -z "$pubspec_ver" ]; then
  echo "cannot read version from pubspec.yaml" >&2
  exit 1
fi
current_ver="$(sed -n 's/^pkgver=\(.*\)$/\1/p' "$PKGBUILD")"
if [ "$current_ver" != "$pubspec_ver" ]; then
  echo "==> Syncing pkgver $current_ver -> $pubspec_ver in PKGBUILD"
  sed -i "s/^pkgver=.*$/pkgver=$pubspec_ver/" "$PKGBUILD"
fi

# ---- Build.
echo "==> Building release bundle (version $pubspec_ver)"
flutter build linux --release

# ---- Stage makepkg sources into the work dir under build/.
echo "==> Staging package sources into $WORK_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp "$SRC_DIR/PKGBUILD" "$SRC_DIR/trayforge.desktop" "$WORK_DIR/"
tar -C build/linux/x64/release/bundle -czf "$WORK_DIR/trayforge-bundle.tar.gz" .
cp assets/trayforge.png "$WORK_DIR/trayforge.png"

# ---- Package. makepkg verifies depends against the local pacman database.
echo "==> Running makepkg"
cd "$WORK_DIR"
makepkg -f -p PKGBUILD

# ---- Keep only the produced package; drop the debug package and work dirs.
rm -f "$WORK_DIR"/trayforge-debug-*.pkg.tar.zst
rm -rf "$WORK_DIR"/src "$WORK_DIR"/pkg
rm -f "$WORK_DIR"/PKGBUILD "$WORK_DIR"/trayforge.desktop \
      "$WORK_DIR"/trayforge-bundle.tar.gz "$WORK_DIR"/trayforge.png

echo "==> Done"
pkg="$(ls "$WORK_DIR"/trayforge-*-x86_64.pkg.tar.zst)"
ls -lh "$pkg"
echo
echo "Install with: sudo pacman -U \"$pkg\""
