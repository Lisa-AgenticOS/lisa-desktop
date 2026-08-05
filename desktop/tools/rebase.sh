#!/usr/bin/env bash
# Rebase the Lisa Desktop patch series onto a new GNOME Shell release.
#
#   desktop/tools/rebase.sh 50.4
#
# This is the entire upstream-tracking procedure. It is a real
# `git rebase` between two real trees, not a re-application of text
# edits, so its failure mode is a conflict you resolve — never a patch
# that lands in the wrong place and builds anyway.
#
# What it does:
#   1. fetches the new tarball and verifies it against the sha256sum
#      GNOME publishes beside it (never a hash typed by a human);
#   2. rebuilds the OLD pin as a git tree and applies the series to it;
#   3. commits the NEW pristine tree on top of the old one;
#   4. `git rebase --onto` moves the series across;
#   5. regenerates patches/ with `git format-patch` and rewrites the pin
#      in the PKGBUILD.
#
# On conflict it stops and tells you where the scratch tree is. That is
# not a failure of the tool: a conflict is the measurement of where the
# fork's delta has grown into code upstream is still moving. ADR-0038
# says to read it that way.
set -euo pipefail

new_ver=${1:-}
[ -n "$new_ver" ] || { echo "usage: ${0##*/} <new-gnome-shell-version>   e.g. 50.4" >&2; exit 2; }

root=$(git rev-parse --show-toplevel)
pkgbuild="$root/desktop/PKGBUILD"
patchdir="$root/desktop/patches"
tools="$root/desktop/tools"

old_ver=$(sed -n 's/^pkgver=//p' "$pkgbuild")
[ -n "$old_ver" ] || { echo "!! cannot read pkgver from $pkgbuild" >&2; exit 1; }
[ "$old_ver" != "$new_ver" ] || { echo "!! already pinned to $new_ver" >&2; exit 1; }

work=$(mktemp -d)
echo ">> rebasing the Lisa Desktop series: $old_ver -> $new_ver"
echo ">> scratch: $work"

fetch() {  # fetch <version>; echoes the verified tarball path
    # One assignment per line: `local` expands all of its arguments
    # before assigning any of them, so `local v=$1 tar=".../$v.tar.xz"`
    # reads $v while it is still unset — which under `set -u` is a
    # crash, and without it would be a silent wrong filename.
    local v=$1
    local major=${1%%.*}
    local tar="$work/gnome-shell-$v.tar.xz"
    local base="https://download.gnome.org/sources/gnome-shell/$major"
    curl -fsSL -o "$tar" "$base/gnome-shell-$v.tar.xz"
    # Upstream publishes the checksum next to the artefact. We verify
    # against that file, so no hash in this repository was ever guessed
    # or copied by hand.
    curl -fsSL -o "$tar.sums" "$base/gnome-shell-$v.sha256sum"
    local want
    want=$(awk -v f="gnome-shell-$v.tar.xz" '$2 == f { print $1 }' "$tar.sums")
    [ -n "$want" ] || { echo "!! no sha256 for gnome-shell-$v.tar.xz in the published sums" >&2; exit 1; }
    local got
    got=$(sha256sum "$tar" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "!! sha256 mismatch for gnome-shell-$v.tar.xz: got $got want $want" >&2; exit 1; }
    printf '%s\n' "$want" > "$tar.verified"
    printf '%s\n' "$tar"
}

old_tar=$(fetch "$old_ver")
new_tar=$(fetch "$new_ver")
new_sha=$(cat "$new_tar.verified")
echo ">> verified gnome-shell-$new_ver.tar.xz  sha256 $new_sha"

# 1. the old pin, plus the series -> branch `lisa`
mkdir -p "$work/tree"
tar -xf "$old_tar" -C "$work" && mv "$work/gnome-shell-$old_ver"/* "$work/gnome-shell-$old_ver"/.[!.]* "$work/tree/" 2>/dev/null || true
rmdir "$work/gnome-shell-$old_ver" 2>/dev/null || true
bash "$tools/apply-series.sh" "$work/tree" "$patchdir" "gnome-shell $old_ver (pristine upstream release tarball)"

cd "$work/tree"
git branch -f lisa HEAD
git checkout -q upstream

# 2. the new pin, committed on top of the old one, so the rebase has a
#    real merge base and git can follow renames across the release.
git rm -rq --cached .
find . -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
tar -xf "$new_tar" --strip-components=1 -C .
git add -A -f
git commit -q -m "gnome-shell $new_ver (pristine upstream release tarball)"
git tag -f upstream-new >/dev/null

# 3. move the series across
echo ">> git rebase --onto upstream-new upstream lisa"
if ! git rebase --onto upstream-new upstream lisa; then
    cat >&2 <<EOF

!! the series does not apply to gnome-shell $new_ver.

   Resolve it in place, then re-run format-patch by hand:
       cd $work/tree
       git status              # what conflicts
       git rebase --continue   # when resolved
       git format-patch -o $patchdir --no-signature upstream-new..lisa

   The scratch tree is NOT deleted. Which patch conflicted, and against
   which upstream hunk, is the useful output of this run: it is where
   the fork has grown into code upstream is still changing (ADR-0038,
   "a rebase that conflicts is information").
EOF
    exit 1
fi

# 4. regenerate the series and re-pin
rm -f "$patchdir"/*.patch
# --full-index is not cosmetic: `git am --3way` finds the pre-image blob
# by the hash on the patch's index line, and format-patch abbreviates it
# by default. An abbreviated hash makes the next rebase fall back to
# plain context matching, which is the failure mode this whole design
# exists to avoid.
# --zero-commit so a regenerated series that changed nothing is
# byte-identical to the old one, instead of churning on every run.
git format-patch -o "$patchdir" --no-signature --zero-commit --full-index \
    upstream-new..lisa >/dev/null
# Re-pinning is an assertion, not an edit.
#
# This was two `sed -i.bak` calls, and the second one was
# `0,/^  '[0-9a-f]\{64\}'$/s//.../`. `0,/re/` is a GNU extension: BSD
# sed accepts the script, exits 0, and changes nothing. The 50.3 -> 50.4
# rebase was run on a macOS host and produced a PKGBUILD carrying the
# NEW pkgver beside the OLD tarball hash — an incoherent pin, written
# silently, by the tool whose own README is an argument against `sed`
# that exits 0 having matched nothing (#5).
#
# So: awk with no GNU-only syntax, and a comparison that makes "matched
# nothing" a hard failure. The guard now exists for the pin the way
# `git am --3way` exists for the series.
repin() {  # repin <awk-program> <value>
    awk -v val="$2" -v q="'" "$1" "$pkgbuild" > "$pkgbuild.new"
    if cmp -s "$pkgbuild" "$pkgbuild.new"; then
        echo "!! re-pinning $pkgbuild matched nothing — the PKGBUILD's shape moved" >&2
        rm -f "$pkgbuild.new"
        exit 1
    fi
    mv "$pkgbuild.new" "$pkgbuild"
}
repin '/^pkgver=/ && !done { $0 = "pkgver=" val; done = 1 } { print }' "$new_ver"
# Only the FIRST sha256sums entry is the upstream tarball; the second is
# SKIP for our own git archive and must not be touched. Matching
# [0-9a-f]+ rather than a {64} interval keeps this off BSD awk's
# interval-expression support; 'SKIP' cannot match it either way.
repin '!done && $0 ~ "^  " q "[0-9a-f]+" q "$" { $0 = "  " q val q; done = 1 } { print }' "$new_sha"

cat <<EOF

>> done.
   pin:      gnome-shell $old_ver -> $new_ver  (sha256 $new_sha)
   series:   $(ls "$patchdir"/*.patch 2>/dev/null | wc -l | tr -d ' ') patch(es), regenerated
   scratch:  $work  (kept — 'git diff upstream-new' there is the whole fork)

   Next: review the regenerated patches, bump pkgrel to 1, rebuild, and
   re-run desktop/smoke.sh against the built package. A rebase is not
   done until the shell has been booted again.
EOF
