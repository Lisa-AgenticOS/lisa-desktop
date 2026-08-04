#!/usr/bin/env bash
# Build lisa-desktop-shell from the current git HEAD.
# Run on Arch (host or container) as an unprivileged user with
# base-devel + the PKGBUILD's makedepends installed.
# Usage: desktop/build-package.sh [outdir]
#
# Deliberately a second script rather than a flag on the root
# build-package.sh: this one compiles a desktop shell and takes minutes,
# the other packages JavaScript and takes seconds. Coupling them would
# make every shell-surface change wait for a GNOME Shell build.
#
# The "lisa" source tarball is a git archive of HEAD, so what gets
# packaged is exactly what is committed — a dirty tree cannot leak into
# a package. The upstream tarball is fetched by makepkg and checked
# against the sha256 pinned in the PKGBUILD.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
out=${1:-"$root/out"}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ver=$(sed -n 's/^pkgver=//p' "$root/desktop/PKGBUILD")
echo ">> lisa-desktop-shell (gnome-shell $ver) -> $out"

# desktop/ and LICENSE only: the shell fork has no use for shell/ or
# ime/, and a 30 MB source tarball of unrelated JavaScript inside every
# package is noise in the [lisa] index.
git -C "$root" archive --prefix 'lisa/' -o "$work/lisa-desktop-tree.tar.gz" HEAD desktop LICENSE
cp "$root/desktop/PKGBUILD" "$work/"

# -d: the runtime depends include our own packages (lisa-cli et al) that
# are not in a hosted repo yet. Everything build() actually executes
# must still be installed, or the build fails on its own terms.
(cd "$work" && makepkg --noconfirm --force -d)

mkdir -p "$out"
cp "$work"/*.pkg.tar.* "$out/"
echo ">> packages:"
ls -l "$out"
