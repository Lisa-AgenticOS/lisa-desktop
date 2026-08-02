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

Everything here is GJS/JS/CSS plus one C++ fcitx5 addon; it talks to
the OS only over D-Bus (`dev.lisaos.*` names) and the fcitx5 addon's
HTTP client. There is no build step for the JS: on a Lisa OS device the
files are copied into place by the `lisa` package. Component READMEs in
each directory carry the smallest real usage example.

## Status, honestly

- The GNOME Shell vendor tree (ADR-0038 step 1) is **not here yet** —
  this repo currently holds the extension-era code that the fork will
  absorb. Vendoring at a pinned signed tag is the next step.
- This repo does **not yet produce a package**. Until it does, the
  `lisa-os` monorepo's copies of these directories remain the ones an
  image ships; per ADR-0039, nothing was deleted there, and removal
  happens only once the package this repo builds is what the image
  installs.

## How to extend it

Read `docs/PLAN.md` §5.7 and ADR-0035/0038 in `lisa-os` first — the
architecture and its reasons live there. Rules that bind this repo:
identity from the transport (ADR-0033), no network in shell surfaces,
reverse-DNS names are `dev.lisaos.*`/`app.lisaos.*` (ADR-0016).

## Limits

- Validated on one reference device (iMac18,2). No aarch64 machine has
  rendered this desktop.
- CI for this repo is not set up yet; the lint/test gates still run in
  `lisa-os`.
