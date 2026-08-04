#!/usr/bin/env bash
# Turn a pristine upstream source tree into the Lisa Desktop tree.
#
#   apply-series.sh <tree> <patchdir> <label>
#
# The tree becomes a git repository whose first commit is upstream
# exactly as shipped, and whose remaining commits are the patch series.
# Afterwards `git log upstream..HEAD` in that tree IS the fork's delta,
# and `git diff upstream` is the whole of it — there is nowhere else for
# divergence to hide.
#
# One implementation, three callers: the PKGBUILD's prepare(),
# tools/rebase.sh, and CI. A second copy of this logic is how the build
# and the rebase start disagreeing about what the fork is.
set -euo pipefail

tree=${1:?usage: apply-series.sh <tree> <patchdir> <label>}
patchdir=${2:?usage: apply-series.sh <tree> <patchdir> <label>}
label=${3:?usage: apply-series.sh <tree> <patchdir> <label>}

cd "$tree"

git init -q .
git config user.name  'Lisa Desktop vendoring'
git config user.email 'lisa-desktop@lisaos.dev'
git config gc.auto 0
git config commit.gpgsign false
# -f: upstream ships a .gitignore. Without -f the base commit would be
# the tarball minus whatever upstream ignores, and every later three-way
# merge would be resolving against a tree that is not the one we build.
git add -A -f
git commit -q -m "$label"
git tag -f upstream >/dev/null

shopt -s nullglob
series=("$patchdir"/*.patch)
if [ ${#series[@]} -eq 0 ]; then
    echo ":: no patches — this tree is pristine upstream"
else
    echo ":: applying ${#series[@]} patch(es) from $patchdir"
    # --3way is the point of the whole design: a hunk carries the blob
    # hash of the file it was cut from, so when upstream moves the code
    # out from under it git either merges it correctly or stops with a
    # conflict. There is no third outcome in which it applies somewhere
    # wrong and the build succeeds — which is precisely the outcome a
    # `sed -i` anchor produces, silently, by exiting 0 on no match.
    git am --3way --keep-non-patch "${series[@]}"
fi

# Nothing may be edited in place. If this fires, someone put divergence
# somewhere that no rebase will ever carry forward.
test -z "$(git status --porcelain)" || {
    echo "!! the tree has uncommitted changes — the delta must live in $patchdir" >&2
    git status --porcelain >&2
    exit 1
}

echo ":: delta is $(git rev-list --count upstream..HEAD) commit(s) on top of $label"
