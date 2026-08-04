# `desktop/` — the GNOME Shell fork

This is Lisa Desktop itself: the vendored GNOME Shell source, the patch
series that will become the fork's divergence, and the packaging that
turns them into a session GDM can offer.

It is not the same thing as `../shell/`. That directory holds the
*extensions* of the extension era — the code ADR-0038 step 3 absorbs
into this fork and then deletes. Until then the two coexist and neither
touches the other.

## What it does

Builds `lisa-desktop-shell`: GNOME Shell, pinned at a verified upstream
release, built under Lisa's own name into a private prefix, plus the
five files that make it a selectable session.

At this pin **the Lisa delta is empty**. That is the point of ADR-0038
step 2, not a stage we have not reached yet: the milestone is "can we
own this", and it is only answered honestly by a build with nothing of
ours in it. `patches/` holds exactly one patch and it is Arch's, not
ours — see below.

| What | Where |
|---|---|
| The pin (upstream version + sha256) | `PKGBUILD`, lines `pkgver=` and the first `sha256sums` entry |
| The delta | `patches/*.patch` |
| Applying the delta | `tools/apply-series.sh` |
| Tracking upstream | `tools/rebase.sh` |
| What the fork actually changes | `tools/js-delta.py` |
| The session | `session/` |
| Proof it boots | `smoke.sh` |

## How it works

### The pin

Upstream is a **release tarball verified against the sha256 GNOME
publishes beside it**, not a git tag:

```
gnome-shell-50.3.tar.xz
  sha256 450458c44a26d25a9b84288e12b9005d4c5c44648cfc6b790be19a05de7f1735
  from   https://download.gnome.org/sources/gnome-shell/50/
  and    .../gnome-shell-50.3.sha256sum publishes that same hash
```

Arch builds gnome-shell from a git tag instead, with a comment
explaining that GNOME Shell's tags carry SSH signatures makepkg cannot
verify — so the tag pin is, in practice, unverified. A hash of an
immutable artefact that upstream itself publishes is the stronger pin,
and it is the one thing in this directory that a human never types:
`tools/rebase.sh` fetches the `.sha256sum` file and writes the PKGBUILD
line from it.

The release tarball also ships `subprojects/gvc`, `libshew`,
`jasmine-gjs` and both extensions subprojects as real directories, so
nothing is fetched during the build.

### The delta is a patch series, not text surgery

`os/packages/gnome-control-center-lisa/PKGBUILD` in the `lisa-os`
monorepo is the cautionary example this directory was written against.
It applies its delta with ~150 lines of `sed` and `awk` against textual
anchors, guarded by nine hand-written `grep`s that "fail loudly if
upstream moved them". It works, and it does not scale, for one specific
reason:

> `sed -i 's/x/y/' file` that matches nothing **exits 0**.

Every in-place edit therefore has three outcomes — applied, not applied,
or applied somewhere unintended — and only a guard somebody remembered
to write distinguishes them. The guard is a separate artefact from the
edit it protects; nothing forces the two to stay in step, and adding an
edit without adding a guard is invisible in review.

A patch series has two outcomes. `git am --3way` carries, per hunk,
three lines of context and the **blob hash of the file the hunk was cut
from**. It either merges the change into its correct place or it stops
with a conflict. There is no silent third case, the check exists for
every hunk automatically, and nobody has to remember it.

Everything else follows from that:

- **The delta is reviewable as a series.** Each patch has an author, a
  subject and a rationale in its commit message. `git log` over the
  applied tree says what the fork changed and why. A 150-line `awk`
  block says neither.
- **Divergence has exactly one home.** `tools/apply-series.sh` asserts
  that after the series is applied the tree is `git status`-clean. An
  edit made anywhere else fails the build, so "the fork's delta" is a
  computable thing (`git diff upstream`) rather than a claim.
- **Patches are independently droppable.** The first one in the series
  is not ours and should disappear on a future rebase; dropping it is
  `rm`, not archaeology through a script.

Concretely, `prepare()` makes the pristine tarball commit 1 of a
throwaway git repository, tags it `upstream`, and applies the series on
top. The build then compiles a git worktree whose history *is* the
fork.

### What is in `patches/` right now

One patch, and it is worth being precise about it:

`0001-Fix-build-with-libical-4.patch` — Antonio Rojas's one-line fix
from Arch's own gnome-shell package. GNOME Shell 50.3 does not compile
against libical 4 (Arch ships 4.0.4); the calendar server's function
pointer type lost a `const`. Arch carries it, so the shell the reference
device runs already contains it.

This is the first thing step 2 found that the issue did not expect: the
delta does not start empty in the sense of "no patches", it starts empty
in the sense of "nothing of Lisa's". Carrying a distro compatibility fix
is exactly the case the series format handles better than anchors — it
has a real author, a real reason, and it should be dropped, not edited,
when upstream fixes it.

The convention for the series: **compat and backport patches sort first,
Lisa's own delta sorts after them.** `git format-patch` renumbers on
every rebase, so the boundary is documented here and in each patch's
own commit message rather than encoded in filenames.

### Parallel install: a private prefix, and no source changes

The package installs the entire upstream build under
`/usr/lib/lisa-desktop`. Nothing else about the build is altered.

That works because every installed path in GNOME Shell's meson derives
from `prefix` — `bindir`, `libdir`, `libexecdir`, `datadir`,
`pkgdatadir`, `pkglibdir`, the systemd user unit directory (it is read
from `systemd.pc` but re-evaluated with our prefix) and even the
gnome-control-center keybindings directory. The binary compiles its own
`datadir`, typelib directory and pkglibdir into itself
(`-DSHELL_TYPELIB_DIR`, `-DGNOME_SHELL_PKGLIBDIR`) and sets an
`install_rpath` covering both, so a relocated build is self-consistent
with **zero patches**. Separation is a packaging decision; the source
stays byte-identical, which is the acceptance criterion.

Two guards in `package()` keep it that way, and both are set checks over
the whole payload rather than a list of paths somebody thought of:

1. everything the upstream build installs must land inside the private
   prefix — if a future release adds an install directory that escapes,
   the build stops instead of overwriting a `gnome-shell` file;
2. every path this package owns *outside* the private prefix must have
   `lisa` in its basename.

Five files live outside the prefix, and together they are the whole
difference between "a binary exists" and "GDM offers Lisa Desktop":

| File | Why |
|---|---|
| `/usr/share/wayland-sessions/lisa-desktop.desktop` | what GDM lists |
| `/usr/share/gnome-session/sessions/lisa.session` | what `gnome-session --session=lisa` looks up |
| `/usr/lib/systemd/user/gnome-session@lisa.target.d/lisa-session.conf` | the one file that makes the session run *our* shell |
| `/usr/lib/systemd/user/lisa-desktop@.service` | the shell unit |
| `/usr/lib/systemd/user/lisa-desktop-disable-extensions.service` | its `OnFailure=` target |

`DesktopNames=GNOME` in the session file is deliberate. `XDG_CURRENT_DESKTOP`
is read by xdg-desktop-portal to choose a backend, by
gsettings-desktop-schemas for per-desktop defaults, and by every
`.desktop` carrying `OnlyShowIn=`. Changing it changes the behaviour of
software that has never heard of Lisa — precisely what step 2 must not
do. The visible name is Lisa Desktop; the compatibility identity stays
GNOME until something concrete needs it not to be.

### Measuring "byte-identical"

```
python desktop/tools/js-delta.py
```

The acceptance criterion of step 2 is not a promise anyone should have
to take on trust. GNOME Shell's whole user interface is JavaScript
compiled into a GResource inside `libshell-18.so`, so the fork's runtime
delta is exactly the set of resources whose bytes differ from the
distribution's `gnome-shell`. The tool loads both libraries, asks GLib
what each registered, and diffs the hashes:

```
:: 197 resources in the fork, 197 in stock
:: identical — the fork's user interface is byte-for-byte the distribution's
```

The comparison is made modulo the install prefix. GNOME Shell compiles
`LOCALEDIR`, `LIBEXECDIR` and `PKGDATADIR` into `js/misc/config.js`, so
that one resource genuinely differs — by exactly those three constants
and nothing else, which was checked by hand the first time the tool went
red. Rather than excusing the whole file (which would hide a real change
made inside it), the fork's bytes have the relocation undone before
hashing.

That first red run is also the tool's positive control: on 197
resources it found the one that differed, and it found it by three
lines.

When the delta stops being empty at step 3, this becomes the fork's
change report — run it with `--allow-delta` and it prints exactly which
interface files Lisa owns.

### Booting it

```
# after installing the package
desktop/smoke.sh 50.3
```

Starts the shell as a headless display server on a private session bus
and asks it over D-Bus what it is:

```
:: booting /usr/lib/lisa-desktop/bin/gnome-shell (headless, private bus)
ShellVersion=50.3
Mode=user
:: Lisa Desktop booted, owned org.gnome.Shell, and reported 50.3 in mode user
```

Owning `org.gnome.Shell` and answering a property read is not a liveness
ping: it means the binary started, mutter brought up a compositor, and
the shell's embedded JavaScript ran all the way through `init.js` to the
point of exporting `/org/gnome/Shell`. A shell that fails anywhere in
that chain never answers. In practice the run also activates
`org.gnome.Shell.CalendarServer`, `.Notifications` and `.Screencast`,
which is more of the desktop than the assertion strictly demands.

Note the readiness condition: the script waits on the *property read*,
not on the bus name. The shell takes `org.gnome.Shell` a beat before it
exports the object, so a name-owner check reports success too early and
the read that follows fails — a working shell reported as broken.

It touches no seat, no login session and no display, so it is safe to
run on a machine somebody is working on. In a container, set
`LISA_SMOKE_MOCK_LOGIND=1`: there is no systemd-logind there, and the
shell asks logind for the session while building its `LayoutManager` —
it dies in JavaScript at that line, before it would own anything. The
mock is a prop for the environment, not for the thing under test; the
binary, the compositor and every line of JavaScript are the real ones.
Never set it on a real machine.

### Tracking upstream

```
desktop/tools/rebase.sh 50.4
```

Fetches and verifies the new tarball, rebuilds the *old* pin as a git
tree, applies the series to it, commits the new pristine tree on top,
and runs `git rebase --onto`. On success it regenerates `patches/` with
`git format-patch` and rewrites the pin in the PKGBUILD. On conflict it
stops, keeps the scratch tree, and tells you where it is.

A conflict is the intended output in that case, not a malfunction: it is
the measurement of where the fork's delta has grown into code upstream
is still moving. ADR-0038 asks for it to be read that way.

The rebase is a real three-way merge between two real trees, which is
the second reason to prefer a series over anchors — there is no way to
"rebase" a `sed` expression.

## How to extend it

Add to the fork by adding a patch, never by editing in place:

```
# get a tree with the series already applied
cd $(mktemp -d) && curl -O https://download.gnome.org/sources/gnome-shell/50/gnome-shell-50.3.tar.xz
tar -xf gnome-shell-50.3.tar.xz
bash /path/to/lisa-desktop/desktop/tools/apply-series.sh \
     gnome-shell-50.3 /path/to/lisa-desktop/desktop/patches \
     "gnome-shell 50.3 (pristine upstream release tarball)"

cd gnome-shell-50.3
# ...edit, commit with a message that says why...
git format-patch -o /path/to/lisa-desktop/desktop/patches --no-signature upstream..HEAD
```

The commit message is the patch's documentation and it is the only place
the reason survives a rebase. Write it for the person doing the 50.7
rebase, not for yourself today.

Read ADR-0038 in `lisa-os` first. Step 3 (absorbing `../shell/`) and
step 4 (the prompt in the dock) are where the delta stops being empty.

## Limits

Stated as of this pin, and only what has actually been run:

- **Proven, by running it:** the package builds from the pinned tarball;
  the series applies; nothing installs outside the private prefix;
  `pacman -U` installs it on a system that already has stock
  gnome-shell, with no file conflicts; its 197 UI resources are
  byte-identical to Arch's `gnome-shell` 1:50.3-1; and the shell boots
  headless, owns `org.gnome.Shell` and reports 50.3 in mode `user`. CI
  runs all of it on every push. `smoke.sh` has been checked against
  three deliberate failures — wrong expected version, missing binary,
  a shell that cannot start — and reports each one correctly.
- **Proven on the reference device, without installing anything:** all
  134 shared libraries the fork links resolve on the iMac running Lisa
  OS 20260804.76, and it binds the same `libmutter-18.so.0` as the
  device's own gnome-shell. The package was unpacked read-only under
  `/var/tmp/lisa-desktop-stage` for that check; nothing was installed
  and nothing in `/usr` was touched.
- **Not proven: a real login.** Nobody has selected "Lisa Desktop" at a
  GDM greeter and got a desktop. The reference iMac runs an immutable
  A/B image with no package manager on it, so this package cannot be
  installed there without building it into an image — which is
  `lisa-os`'s side of the work, not this repo's. Until that happens,
  "boots" means what `smoke.sh` proves and no more. In particular
  nothing here exercises GDM's session list, gnome-session's
  `--session=lisa` lookup, or the `gnome-session@lisa.target` drop-in;
  those files were written against the 50.3 source and the device's own
  units (`gnome-session@%s.target` is the format string in
  `gnome-session-init-worker`), but written is not run.
- **The boot proof runs against a mock logind.** Session registration,
  seat handling and anything logind-shaped is therefore untested.
- **`depends=(gnome-shell)` is transitional.** GNOME Shell ships D-Bus
  *activatable* helpers (CalendarServer, Notifications, Screencast,
  ScreenSaver, Extensions) whose `.service` files must sit in a
  directory the session bus scans. A private prefix cannot claim that
  namespace without file-conflicting with stock gnome-shell, and the
  names those services are requested under are baked into the shell's
  JavaScript — so renaming them is a source change, and step 2 has none.
  While the pin is 50.3 the stock copies are the same code, so behaviour
  is identical; the dependency makes that an enforced fact rather than a
  hope. Step 3 resolves it.
- **x86_64 only.** ADR-0021's aarch64 lane is unbuilt here. The `arch=`
  line will be widened when there is a build behind it.
- **Licence.** This package is GPL-3.0-or-later — GNOME Shell's licence,
  which a derived work cannot relicense downwards. The repository's
  GPL-2.0-only `LICENSE` (ADR-0005) covers Lisa's own code and is
  installed alongside upstream's `COPYING`. Anything added to `patches/`
  is a derivative of GPL-3.0-or-later code and carries that licence,
  which ADR-0005 and ADR-0038 do not currently say out loud.
