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
release, built under Lisa's own name **in place of** the `gnome-shell`
package, plus the five files that make it a selectable session.

The delta was empty through ADR-0038 step 2, which was the point: the
milestone was "can we own this", and it is only answered honestly by a
build with nothing of ours in it. That question is answered, and
`patches/` now holds **one distro compat fix and one deliberate
divergence** — screen capture (lisa-os#266), described below.

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
gnome-shell-50.4.tar.xz
  sha256 c531939539db316a41aef23670370abd1330d3254f84bcb0f9f4dae5d6e362cf
  from   https://download.gnome.org/sources/gnome-shell/50/
  and    .../gnome-shell-50.4.sha256sum publishes that same hash
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

Two patches, and it is worth being precise about both:

`0001-Fix-build-with-libical-4.patch` — Antonio Rojas's one-line fix
from Arch's own gnome-shell package. GNOME Shell 50.4 does not compile
against libical 4 (Arch ships 4.0.4); the calendar server's function
pointer type lost a `const`. Arch still carries it at 1:50.4-1 — byte
for byte the same patch — so the shell the reference device runs already
contains it.

This is the first thing step 2 found that the issue did not expect: the
delta does not start empty in the sense of "no patches", it starts empty
in the sense of "nothing of Lisa's". Carrying a distro compatibility fix
is exactly the case the series format handles better than anchors — it
has a real author, a real reason, and it should be dropped, not edited,
when upstream fixes it.

`0002-Lisa-Desktop-may-photograph-its-own-screen.patch` — ours, and the
first thing in this directory that makes Lisa Desktop behave unlike
GNOME Shell. See "Screen capture" below.

The convention for the series: **compat and backport patches sort first,
Lisa's own delta sorts after them.** `git format-patch` renumbers on
every rebase, so the boundary is documented here and in each patch's
own commit message rather than encoded in filenames.


### Screen capture: who may photograph this screen

`0002` is the fork's first deliberate divergence, and it exists because
GNOME 50 refuses screen capture to the operating system that ships it.

**What stock does.** `js/ui/screenshot.js` guards
`org.gnome.Shell.Screenshot` with `DBusSenderChecker`, constructed with
two well-known bus names:

```js
this._senderChecker = new DBusSenderChecker([
    'org.gnome.SettingsDaemon.MediaKeys',
    'org.freedesktop.impl.portal.desktop.gnome',
]);
```

and `checkInvocation()` (`js/misc/util.js`) compares the invocation's
sender against the *current owners* of those names:

```js
async _isSenderAllowed(sender) {
    await this._initializedPromise;
    return [...this._allowlistMap.values()].includes(sender);
}
```

Anything else gets `GDBus.Error:org.freedesktop.DBus.Error.AccessDenied:
Screenshot is not allowed`. Those two names are a person pressing Print,
and the portal's interactive-consent dialog. There is no third door, and
the reference device ships no `grim`, `gnome-screenshot`, `spectacle`,
`scrot` or `wf-recorder` either, so the OS cannot see its own screen:
not for the owner, not for CI on real hardware, not for a bug report.

**Why not just add a Lisa bus name.** Because a well-known name is
claimed first-come on a bus every process on the seat can reach. An
allowlist entry for `dev.lisaos.Something` grants screen capture to
whichever process asked the bus for that name first, which is
authorisation obtainable by asking nicely (CLAUDE.md rule 6a). The same
objection retires a command-line flag, a gsettings key and a config
file: each of them is something a caller can arrange to be true.

**What the patch does instead** — identity from the transport
(ADR-0033). Only after upstream's check has already said no, the shell
asks the bus daemon for the peer's credentials (`GetConnectionCredentials`,
which the daemon derives from `SO_PEERCRED`, not from the message), reads
`/proc/<pid>/exe`, and stats it. The caller is authorised only if:

| | why |
|---|---|
| its uid is the uid this shell runs as | the session bus is per-user; the case where that is not true is the case that must not capture this screen |
| `/proc/<pid>/exe` resolves to a direct child of `/usr/lib/lisa/bin` | that directory is installed by the OS image and is read-only to every non-root process |
| that file is a regular file owned by uid 0, not group- or other-writable | otherwise somebody who is not root can replace what runs from there |
| the directory itself is root-owned and not group/other-writable | otherwise somebody who is not root can add to it |
| the exe link does not end in `" (deleted)"` | the binary was unlinked; whatever it was, it is not the file we stat |

So after this patch the callers of `org.gnome.Shell.Screenshot` are:
gnome-settings-daemon's media keys (unchanged), xdg-desktop-portal-gnome
(unchanged), and processes running a root-owned binary out of
`/usr/lib/lisa/bin`. **Not** `gdbus`, `gjs`, `python`, any GJS shell
surface or Lisa app, any agent's shell tool, a copy of the CLI in
`$HOME` — and **not the Lisa CLI's own runtime-channel copy** under
`/var/lib/lisa-apps/payloads/runtime/current/bin/lisa`, which is
`-rwxr-xr-x 1 lisa lisa` on the reference device. An unprivileged update
channel does not get to hand this capability to arbitrary code, so a
`lisa` verb that needs it must run the image-baked binary
(`LISA_NO_CHANNEL=1`, or `/usr/lib/lisa/bin/lisa` directly).

**A capture always flashes.** `flash` is an argument on the D-Bus
method, so a caller can ask for silence; a Lisa-authorised caller does
not get to. The shell forces the flashspot and the shutter sound
whatever the argument said, and logs the calling binary and pid. A
capture nobody can see is a camera with the light disabled, and the
shell is the only participant a caller cannot rewrite.

**What this is not.** It authorises a *binary*, not an intention.
Anyone who can run `/usr/lib/lisa/bin/lisa` can reach what that binary
exposes, and `LD_PRELOAD` into a non-setuid process is available to
whoever owns it. That is deliberate: a guardrail sits between the model
and the machine, never between a person and their own machine
(ADR-0029, ADR-0030). The agent-facing decision — refusing an untrusted
provenance chain, `screen.once`, the Ledger entry (PLAN §5.5,
lisa-os#251, #252) — belongs to the CLI's guard, and lives in `lisa-os`,
not here. What the shell buys is that the capture path is *one auditable
binary* instead of every process on the bus, and that no capture is
invisible.

**Never allowlist an interpreter.** `/usr/bin/gjs` is root-owned and
unwritable too, and allowlisting it would grant this to every script on
the machine. The check is a directory of compiled Lisa binaries
populated by the image, for exactly that reason.

`InteractiveScreenshot`, `SelectArea` and `FlashArea` keep their own
unmodified upstream checks; the patch touches only the three capture
methods that go through `_createScreenshot`.

### Replacing gnome-shell: the stock prefix, and no source changes

The package installs the upstream build at `/usr`, exactly where
`gnome-shell` installs it, and declares:

```
provides=("gnome-shell=1:${pkgver}-${pkgrel}")
conflicts=(gnome-shell)
```

so pacman removes the stock package and every dependency that names
`gnome-shell` is satisfied by this one. Nothing else about the build is
altered — the source is still byte-identical, which is the acceptance
criterion.

**This used to be a private prefix (`/usr/lib/lisa-desktop`), and the
reasons it is not any more are worth keeping**, because they are the
argument for this shape:

- The shell's **D-Bus-activatable helpers** — `org.gnome.Shell.Extensions`,
  `.Notifications`, `.Screencast`, `org.gnome.ScreenSaver`,
  `.CalendarServer` — install their `.service` files into
  `$datadir/dbus-1/services`. At a private prefix that is a directory
  the session bus never scans, which is why the package carried a
  transitional `depends=(gnome-shell)` to borrow stock's copies. At
  `/usr` they are simply ours, with nothing else claiming the names.
- The private prefix needed `GSETTINGS_SCHEMA_DIR` in the shell's unit,
  **and that silently broke the Lisa extensions**. `GSETTINGS_SCHEMA_DIR`
  takes precedence over the XDG chain for every schema it contains;
  `org.gnome.shell` is one of them; and `lisa-shell`'s
  `10_lisa-shell.gschema.override` — the file that sets
  `enabled-extensions` — is compiled into `/usr/share/glib-2.0/schemas`,
  which the private copy shadowed. Measured, not theorised: with the
  variable set, `gsettings get org.gnome.shell enabled-extensions`
  returns `[]`; without it, the override's value. The desktop would have
  booted looking like stock GNOME with none of Lisa's surfaces in it,
  and nothing would have said so.
- `/usr/share/gnome-shell/extensions`, `/usr/share/applications` and
  `/etc/dconf/db/local.d` were fine either way — the shell scans
  `GLib.get_system_data_dirs()` for extensions (`js/misc/fileUtils.js`,
  `collectFromDatadirs`), `Gio.AppInfo` reads XDG_DATA_DIRS, and dconf
  is a settings *backend* that no prefix can move. But "fine for three
  of five" is exactly the class of defect this project keeps producing.

Nothing is co-installed, so none of the private prefix's cost buys
anything. The fallback if this shell does not start is the previous A/B
root slot (ADR-0001), and behind that the dd-able USB image — not a
second desktop on the same disk.

Two guards in `package()` still keep the payload honest, and both are
set checks computed from the payload rather than a list of paths
somebody thought of:

1. the set of paths this package adds to what `meson install` produced
   must equal, exactly, seven paths: the five session files listed
   below plus `usr/share/licenses/lisa-desktop-shell/{LICENSE,
   COPYING.gnome-shell}`. An extra file is
   as much a failure as a missing one, because at this prefix every path
   we add is a path stock `gnome-shell` did not have;
2. every one of those added paths must have `lisa` in it.

CI adds the two claims `package()` cannot make about itself: that
`pacman -Dk` finds no unsatisfied dependency after stock `gnome-shell`
is removed, and that no path stock owned went missing.

Five of those seven are the whole difference between "a binary exists"
and "GDM offers Lisa Desktop":

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
python desktop/tools/js-delta.py OURS.so STOCK.so
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

Both libraries must be named. At the shared prefix the fork and stock
occupy the same path, so a default argument would compare the installed
library with itself and report "identical" having inspected nothing —
the tool refuses same-file input and refuses to run with no arguments.
CI saves the distribution's `libshell-18.so` aside *before* installing
this package, which is the only moment both exist.

The comparison used to be made "modulo the install prefix", because
GNOME Shell compiles `LOCALEDIR`, `LIBEXECDIR` and `PKGDATADIR` into
`js/misc/config.js` and the private-prefix build genuinely differed in
that one resource. **That allowance is gone**, and its removal made the
assertion strictly stronger: at `/usr` those constants hold the same
strings stock's do, so nothing is excused and no substitution can mask a
change.

The first red run is the tool's positive control: on 197 resources it
found the one that differed under the old prefix, and it found it by
three lines.

The delta has stopped being empty, so this is now the fork's change
report: CI runs it with `--allow-delta` and then asserts the printed
list is exactly

```
-- added:
   /org/gnome/shell/misc/lisaSystemCaller.js
-- changed:
   /org/gnome/shell/ui/screenshot.js
```

A resource appearing there that no patch in `patches/` explains is a
finding, not a formality — that is the same "a desktop that fails by
looking like something else needs a test that looks" argument ADR-0038
makes, kept working after the thing it originally proved.

### Booting it

```
# after installing the package
desktop/smoke.sh 50.4
```

Starts the shell as a headless display server on a private session bus
and asks it over D-Bus what it is:

```
:: booting /usr/bin/gnome-shell (headless, private bus)
ShellVersion=50.4
Mode=user
:: Lisa Desktop booted, owned org.gnome.Shell, and reported 50.4 in mode user
```

It then exercises the screenshot gate. The negative control always runs
— the harness's own `gdbus` must be refused — because a gate that
refuses everybody is what stock GNOME already does and would pass any
test that only looked at the positive side. Set `LISA_SMOKE_GATE_PROBE`
to a `gdbus`-compatible binary installed at the authorised path and the
positive control runs too, asserting a real PNG comes back;
`LISA_SMOKE_GATE_PROBE_UNOWNED` points at the same binary in the same
directory but not owned by root, which must still be refused. CI sets
both, using **one program at three locations**, so the variable under
test is the authorisation rather than the caller's behaviour. Neither
variable can grant anything: the gate is compiled into the shell and
reads `/proc/<pid>/exe`.

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

This has now been run for real, on the release that prompted it: the
pin above is the output of `rebase.sh 50.4`, run when Arch moved to
gnome-shell 1:50.4-1 and mutter 50.4-1 on 2026-08-04 (#5). The series
carried with no conflict — `src/calendar-server/gnome-shell-calendar-server.c`
is byte-identical between the two releases, so the libical hunk's
pre-image blob hash did not even change — and Antonio Rojas's authorship
survived. 50.4 is a bugfix release: 35 files, none of them the systemd
units or session files `session/` was written against.

**The run also found a bug in this tool, which is the argument for
running it.** Re-pinning the PKGBUILD used `sed -i "0,/re/s//.../"`.
`0,/re/` is a GNU extension; BSD sed accepts it, exits 0, and changes
nothing — so on a macOS host the rebase produced a PKGBUILD carrying the
new `pkgver` beside the *old* tarball hash, silently. That is precisely
the "`sed` that matches nothing exits 0" failure this whole directory is
designed against, living inside the tool that argues against it. It is
now `awk` with no GNU-only syntax, and a rewrite that matches nothing is
a hard error rather than a no-op.

An earlier dry run had rebased 50.3 *backwards* onto 50.2 in a throwaway
copy, which exercised the merge but could not have exposed that bug: the
pin it wrote was never used.

## How to extend it

Add to the fork by adding a patch, never by editing in place:

```
# get a tree with the series already applied
cd $(mktemp -d) && curl -O https://download.gnome.org/sources/gnome-shell/50/gnome-shell-50.4.tar.xz
tar -xf gnome-shell-50.4.tar.xz
bash /path/to/lisa-desktop/desktop/tools/apply-series.sh \
     gnome-shell-50.4 /path/to/lisa-desktop/desktop/patches \
     "gnome-shell 50.4 (pristine upstream release tarball)"

cd gnome-shell-50.4
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

- **Proven by CI, on every push:** the package builds from the pinned
  tarball; the series applies; what the package adds to upstream's
  payload is exactly the seven named files; `pacman -U` **replaces**
  stock `gnome-shell` (it is gone afterwards, `pacman -T gnome-shell`
  is satisfied by `provides=`, and `pacman -Dk` reports no unsatisfied
  dependency anywhere); no path stock owned went missing; the five
  `org.gnome.Shell.*` activatable services are ours; its 197 UI
  resources are byte-identical to Arch's `gnome-shell` 1:50.4-1 with no
  prefix allowance; and the shell boots headless, owns
  `org.gnome.Shell` and reports 50.4 in mode `user`. `smoke.sh` has
  been checked against three deliberate failures — wrong expected
  version, missing binary, a shell that cannot start — and reports each
  one correctly.
- **Proven on the reference device at the 50.3 pin, and not re-run
  since:** all 134 shared libraries the fork linked resolved on the iMac
  running Lisa OS 20260804.76, and it bound the same `libmutter-18.so.0`
  as the device's own gnome-shell. The package was unpacked read-only
  under `/var/tmp/lisa-desktop-stage` for that check; nothing was
  installed and nothing in `/usr` was touched. **That measurement is
  about the 50.3 package.** The 50.4 rebase has not been staged on the
  device — and it is the more interesting run of the two, because the
  device is what carried mutter 50.4 beside a 50.3 shell (#5).
- **Proven on the reference device at this pin (2026-08-06), and the
  first time a Lisa Desktop build has drawn a frame anyone has seen.**
  The CI-built package was staged under `/var/tmp/lisa-desktop-266` and
  run inside a private mount namespace (`unshare -m`, the stage
  bind-mounted over `/usr/bin/gnome-shell`, `/usr/lib/gnome-shell` and
  `/usr/share/gnome-shell`), so nothing was installed, nothing in `/usr`
  changed, and the session the owner was logged into never saw it. The
  shell came up on the iMac's real GPU (amdgpu, gbm renderer) against
  the device's own mutter 50.4, and an authorised caller captured a
  **3840x2160 PNG of Lisa Desktop** — wallpaper, panel, dock, a Files
  window — while `/usr/bin/gdbus`, the same program at another path, was
  refused in the same run and left no file. The shell logged
  `Lisa Desktop: screen capture by /usr/lib/lisa/bin/probe (pid 35884)`.
  The **unpatched** 50.4 package, staged the same way, refuses the
  authorised caller too — which is what makes the positive control a
  control rather than a formality.
- **Not proven: the live session.** The desktop the owner is logged into
  runs the 50.3 package and is unpatched. Replacing the shell under a
  running Wayland session means ending that session, which is not a
  thing to do remotely to somebody's only machine; it reaches the device
  the ordinary way, through an image release.
- **The screenshot gate, proven by CI on every push:** an unauthorised
  caller is refused with `AccessDenied` and leaves no file; a non-root
  binary in the authorised directory is refused; a root-owned binary in
  it captures a real PNG off the headless virtual monitor. Same program
  in all three, different paths and owners.
- **Not proven: a real login.** Nobody has selected "Lisa Desktop" at a
  GDM greeter and got a desktop. `lisa-os` now builds this package into
  the image (ADR-0039 step 4), so the *opportunity* exists where it did
  not before — but until somebody logs in, "boots" means what
  `smoke.sh` proves and no more. In particular nothing here exercises
  GDM's session list, gnome-session's `--session=lisa` lookup, or the
  `gnome-session@lisa.target` drop-in; those files were written against
  the 50.4 source and the device's own units (`gnome-session@%s.target`
  is the format string in `gnome-session-init-worker`), but written is
  not run.
- **The boot proof runs against a mock logind.** Session registration,
  seat handling and anything logind-shaped is therefore untested.
- **`depends=(gnome-shell)` is gone**, and so is the private prefix it
  existed for. The activatable helpers' `.service` files are installed
  by this package now, under the `org.gnome.Shell.*` names the shell's
  own JavaScript asks for. No source change was needed for that — it
  was always a packaging problem wearing a source-change costume.
- **The stock `gnome.desktop` session entry still exists** in an image
  that installs `gnome-session` (which stays — ADR-0048 keeps
  gnome-session, mutter, GTK4 and the portals as foundation). Selecting
  "GNOME" at the greeter runs `/usr/bin/gnome-shell`, which is this
  package, so it is not a second desktop — it is this one under
  GNOME's session name and without Lisa's session drop-in. GDM's
  fallback session name is the hardcoded string `"gnome"`
  (`gdm-session.c`, `get_fallback_session_name`), so making Lisa
  Desktop the default is done per-user through AccountsService in
  `lisa-os`, not here.
- **x86_64 only.** ADR-0021's aarch64 lane is unbuilt here. The `arch=`
  line will be widened when there is a build behind it.
- **Licence.** This package is GPL-3.0-or-later — GNOME Shell's licence,
  which a derived work cannot relicense downwards. The repository's
  GPL-2.0-only `LICENSE` (ADR-0005) covers Lisa's own code and is
  installed alongside upstream's `COPYING`. Anything added to `patches/`
  is a derivative of GPL-3.0-or-later code and carries that licence,
  which ADR-0005 and ADR-0038 do not currently say out loud.
