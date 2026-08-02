#!/usr/bin/env bash
# Build the lisa-desktop packages from the current git HEAD.
# Run on Arch (host or container) as an unprivileged user with
# base-devel + the PKGBUILD's makedepends installed.
# Usage: build-package.sh [outdir]
#
# Same shape as lisa-os's os/repo-tools/build-packages.sh: the source
# "tarball" is a git archive of HEAD, so what gets packaged is exactly
# what is committed — a dirty tree cannot leak into a package.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
ver=$(sed -n 's/^pkgver=//p' "$root/PKGBUILD")
out=${1:-"$root/out"}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo ">> lisa-desktop $ver -> $out"
git -C "$root" archive --prefix "lisa-desktop-$ver/" -o "$work/lisa-desktop-$ver.tar.gz" HEAD
cp "$root/PKGBUILD" "$work/"

# -d: skip the installed-dependency check. The runtime depends include
# our own packages (lisa-cli, lisa-inferenced), which are not in any
# hosted repo yet — that is lisa-os#171 step 3, and this script is a
# prerequisite of it, not a consumer. Everything build/check actually
# executes (cmake, fcitx5, glib2, gjs) must still be installed, or the
# build fails on its own terms.
(cd "$work" && makepkg --noconfirm --force -d)

mkdir -p "$out"
cp "$work"/*.pkg.tar.* "$out/"
echo ">> packages:"
ls -l "$out"
