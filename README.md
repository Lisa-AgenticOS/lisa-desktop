# Lisa Desktop

The desktop of [Lisa OS](https://github.com/Lisa-AgenticOS/lisa-os):
the Shell surfaces, and the input method that summons them. Extracted
from the `lisa-os` monorepo on 2026-08-02 with full history
(ADR-0006 appendix, ADR-0039), because ADR-0038 decided Lisa Desktop
is a **hard fork of GNOME Shell's JavaScript** — a codebase with its
own upstream, its own rebase cadence, and its own release channel.

## What it does

| Path | Surface |
|---|---|
| `desktop` | **The fork itself** — vendored GNOME Shell, the patch series, and the packaging that makes it a session (ADR-0038 step 2) |
| `shell/desktop` | The Shell extension that makes GNOME look like Lisa (dock, panel, wordmark) — the code ADR-0038 step 3 absorbs into the fork |
| `shell/overlay-extension` | The `dev.lisaos.Overlay1` backend + transient prompt overlay |
| `shell/assistant` | Lisa Assistant — the persistent chat window |
| `shell/consent` | The `dev.lisaos.Consent1` daemon — the consent surface, split from the model host (ADR-0035 §4) |
| `shell/settings` | Lisa Settings app |
| `shell/launcher` | Search-provider launcher surfaces |
| `shell/ledger-app` | The Ledger viewer |
| `shell/testing` | The GJS test harness the other surfaces' tests run on |
| `ime/fcitx5-lisa` | fcitx5 addon: double-Shift summon, everywhere text is typed |

Note on history: commit messages carry `#NNN` issue references from the
monorepo era. They refer to
[`lisa-os` issues](https://github.com/Lisa-AgenticOS/lisa-os/issues),
not to this repo's tracker — GitHub will autolink them to the wrong
place.

## How it works

`shell/` and `ime/` are GJS/JS/CSS plus one C++ fcitx5 addon; they talk
to the OS only over D-Bus (`dev.lisaos.*` names) and the fcitx5 addon's
HTTP client. There is no build step for that JS. `desktop/` is the
opposite: a C and JavaScript codebase vendored from upstream, compiled,
and packaged — see `desktop/README.md`, which is where the vendoring
and rebase strategy is written down.

Two package streams, deliberately separate, because one takes seconds
and one takes minutes:

| Build | Produces | Gate |
|---|---|---|
| `build-package.sh` | `lisa-desktop`, `lisa-desktop-ime` | `.github/workflows/package.yml` |
| `desktop/build-package.sh` | `lisa-desktop-shell` | `.github/workflows/desktop.yml` |

## Status, honestly

- **The GNOME Shell fork exists and builds** (ADR-0038 step 2, `desktop/`):
  pinned at the 50.3 release tarball, verified against the sha256 GNOME
  publishes, installed at `/usr` **in place of** `gnome-shell`
  (`provides=`/`conflicts=`). Its delta at this pin contains nothing of
  Lisa's — that is the milestone, not a shortfall. CI builds it, proves
  the replacement leaves no unsatisfied dependency and drops no file
  stock owned, proves its 197 UI resources are byte-identical to
  Arch's, and boots it headless.
- **Nobody has logged into it.** `lisa-os` now installs this package
  into the image from the `[lisa]` index (ADR-0039 step 4) and makes it
  the default session, so the opportunity exists — but until a person
  logs in, "boots" means what `desktop/smoke.sh` proves and no more.
- The extension-era code in `shell/` is untouched by the fork and still
  the thing an image ships. Per ADR-0039 nothing was deleted in the
  monorepo, and removal happens only once the packages this repo builds
  are what the image installs.

## How to extend it

Read `docs/PLAN.md` §5.7 and ADR-0035/0038 in `lisa-os` first — the
architecture and its reasons live there. Rules that bind this repo:
identity from the transport (ADR-0033), no network in shell surfaces,
reverse-DNS names are `dev.lisaos.*`/`app.lisaos.*` (ADR-0016).

## Limits

- Validated on one reference device (iMac18,2). No aarch64 machine has
  rendered this desktop, and `lisa-desktop-shell` is `arch=(x86_64)`
  because that is the only architecture it has been built on.
- CI here builds and boots the packages; the JS lint gate still runs in
  `lisa-os`.
- `lisa-desktop-shell` is GPL-3.0-or-later, not this repo's
  GPL-2.0-only: it is derived from GNOME Shell and a derived work cannot
  be relicensed downwards. See `desktop/README.md`.
