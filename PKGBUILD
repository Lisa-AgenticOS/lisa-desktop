# Maintainer: Lisa OS project <https://github.com/Lisa-AgenticOS/lisa-desktop>
# The desktop of Lisa OS, packaged from its own repo (ADR-0039: the
# PKGBUILD lives with the source it builds). Built from a git-archive
# tarball produced by build-package.sh — checksum SKIP because the
# tarball is generated locally from git HEAD; the hosted [lisa] repo
# ships signed packages instead.
#
# Two packages from one tree because they have different natures:
# lisa-desktop is pure GJS (arch=any), lisa-desktop-ime links
# Fcitx5Core (compiled, per-arch). What this does NOT ship, on
# purpose: the apps (Surfer, Mail, Preview) — those are lisa-apps,
# from their own repo. The monorepo's lisa-shell package ships both
# halves today; these packages exist so the image can stop needing it
# (lisa-os#171 step 4).

pkgbase=lisa-desktop
pkgname=(lisa-desktop lisa-desktop-ime)
pkgver=0.1.0
pkgrel=1
pkgdesc="Lisa Desktop: the shell surfaces and input method of Lisa OS"
arch=(x86_64 aarch64)
url="https://github.com/Lisa-AgenticOS/lisa-desktop"
license=(GPL-2.0-only)
# glib2: glib-compile-schemas for the overlay keybinding schema.
# cmake + fcitx5: the IME addon (PLAN §5.7.3 layer 2, ADR-0007).
# gjs: check() runs the GJS test suites.
makedepends=(glib2 cmake fcitx5 gjs)
# !debug: makepkg's default debug option split a lisa-desktop-debug
# symbols package out of the IME build and it rode the first v0.1.0
# release into the [lisa] index as noise. Nobody debugs the addon from
# stripped distro symbols; they rebuild it.
options=(!debug)
source=("$pkgbase-$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
    cd "$pkgbase-$pkgver"
    cmake -S ime/fcitx5-lisa -B build-ime \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build-ime
}

check() {
    cd "$pkgbase-$pkgver"
    # Every shell surface's unit tests, with the runtime the desktop
    # actually uses — no node fallback here, unlike the dev-host
    # justfile: if it doesn't pass under gjs it doesn't work on Lisa.
    local t
    for t in shell/*/tests/*.test.js; do
        [ -e "$t" ] || continue
        echo "== $t"
        gjs -m "$t"
    done
    ( cd build-ime && ctest --output-on-failure )
}

package_lisa-desktop() {
    pkgdesc="Lisa Desktop: assistant overlay, semantic launcher, Ledger app, consent surface (PLAN §5.7)"
    # Pure GJS — no compiled code, so one package serves every arch.
    arch=(any)
    # gjs runs the surfaces; libadwaita (pulls gtk4) renders them;
    # lisa-cli is how surfaces reach the substrate (CLAUDE.md rule 7);
    # libqalculate ships qalc, the launcher's calculator lane (§5.7.2).
    depends=(gjs libadwaita lisa-cli libqalculate)
    optdepends=('gnome-shell: overlay + launcher + desktop Shell extensions (GNOME 46+)')
    cd "$pkgbase-$pkgver"

    # Same install location as the monorepo's lisa-shell package, so
    # D-Bus activation files and desktop entries keep working when the
    # image switches provider. shell/settings stays unshipped for the
    # same reason it always has (merged into GNOME Settings as the
    # Intelligence panel, ADR-0012 v2): two settings surfaces on one
    # machine is how the wrong one gets edited.
    local share="$pkgdir/usr/share/lisa/shell"
    install -d "$share"
    cp -a shell/overlay-extension shell/launcher shell/desktop \
        shell/ledger-app shell/assistant shell/consent "$share/"
    rm -rf "$share"/*/tests
    glib-compile-schemas "$share/overlay-extension/schemas"

    # GNOME Shell loads system extensions from
    # /usr/share/gnome-shell/extensions/<uuid>; symlinks keep
    # /usr/share/lisa/shell the single install location.
    install -d "$pkgdir/usr/share/gnome-shell/extensions"
    ln -s /usr/share/lisa/shell/overlay-extension \
        "$pkgdir/usr/share/gnome-shell/extensions/lisa-overlay@lisa-os.org"
    ln -s /usr/share/lisa/shell/launcher \
        "$pkgdir/usr/share/gnome-shell/extensions/lisa-launcher@lisa-os.org"
    ln -s /usr/share/lisa/shell/desktop \
        "$pkgdir/usr/share/gnome-shell/extensions/lisa-desktop@lisa-os.org"

    # D-Bus activation: overlay backend (§5.7.1), push-to-talk voice
    # (§5.7.5 — same process, but activation is per-name), and the
    # consent surface (ADR-0035 §4 — without this file agentd's check
    # has nothing to point at and every confirmation lands in the
    # Absent branch).
    install -Dm644 shell/overlay-extension/backend/dev.lisaos.Overlay1.service \
        "$pkgdir/usr/share/dbus-1/services/dev.lisaos.Overlay1.service"
    install -Dm644 shell/overlay-extension/backend/dev.lisaos.Voice1.service \
        "$pkgdir/usr/share/dbus-1/services/dev.lisaos.Voice1.service"
    install -Dm644 shell/consent/dev.lisaos.Consent1.service \
        "$pkgdir/usr/share/dbus-1/services/dev.lisaos.Consent1.service"

    # Launcher entries + assistant icon.
    install -Dm644 shell/ledger-app/app.lisaos.LedgerApp.desktop \
        "$pkgdir/usr/share/applications/app.lisaos.LedgerApp.desktop"
    install -Dm644 shell/assistant/app.lisaos.Assistant.desktop \
        "$pkgdir/usr/share/applications/app.lisaos.Assistant.desktop"
    install -Dm644 shell/assistant/lisa-assistant-symbolic.svg \
        "$pkgdir/usr/share/icons/hicolor/scalable/apps/lisa-assistant-symbolic.svg"

    # Session defaults: extensions on, Super+Space search,
    # Super+Shift+Space assistant, input switcher on Ctrl+Super+Space.
    install -Dm644 packaging/10_lisa-shell.gschema.override \
        "$pkgdir/usr/share/glib-2.0/schemas/10_lisa-shell.gschema.override"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}

package_lisa-desktop-ime() {
    pkgdesc="Lisa Desktop input-method addon: writing tools + double-tap-Shift summon (PLAN §5.7.3 layer 2)"
    # fcitx5 is the runtime, not just a build dep: this is an addon
    # loaded into its process. lisa-inferenced does the proofreading —
    # the addon holds no model logic (ADR-0007).
    depends=(fcitx5 lisa-inferenced)
    optdepends=(
        'fcitx5-gtk: GTK2/3/4 apps'
        'fcitx5-qt: Qt5/6 apps'
        'fcitx5-configtool: change the trigger key or turn the gesture off'
    )
    cd "$pkgbase-$pkgver"
    DESTDIR="$pkgdir" cmake --install build-ime

    # Make fcitx5 start with the session and be the input method GTK/Qt
    # apps talk to — without these, every file is present, the gesture
    # is dead, and nothing logs why.
    install -Dm644 packaging/lisa-ime.sh \
        "$pkgdir/etc/profile.d/lisa-ime.sh"
    install -Dm644 packaging/fcitx5-lisa-autostart.desktop \
        "$pkgdir/etc/xdg/autostart/fcitx5-lisa.desktop"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
