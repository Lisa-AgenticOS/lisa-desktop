#!/usr/bin/env python3
"""What does Lisa Desktop actually change about the shell you see?

    desktop/tools/js-delta.py [--allow-delta] [FORK_LIBSHELL] [STOCK_LIBSHELL]

GNOME Shell's entire user interface is JavaScript compiled into a
GResource that is linked *into* libshell-<abi>.so and registered by a
static constructor (ADR-0038's "Mechanism, corrected": there is no
runtime JS swap in 50.x, the fork is a rebuild). So the fork's runtime
delta is exactly the set of resources whose bytes differ between our
libshell and the distribution's.

That turns "byte-identical to stock GNOME Shell" from an assertion into
a measurement, which is the acceptance criterion of ADR-0038 step 2. It
keeps earning its place afterwards: once the delta is non-empty this
prints the precise list of interface files the fork owns, so a reviewer
never has to take a PKGBUILD's word for what it changed.

The resource is not in a named ELF section (meson compiles it to C, it
lands in .rodata), so `gresource list` cannot read it. Loading the
library and asking GLib what it registered is the only honest way to
enumerate it -- and it reads the same bytes the shell will.

The comparison is made modulo the install prefix. The fork is built
into /usr/lib/lisa-desktop, and GNOME Shell compiles its own LOCALEDIR,
LIBEXECDIR and PKGDATADIR into js/misc/config.js -- so that one file
differs for a reason that is packaging, not divergence. Rather than
excusing the file wholesale (which would hide a real change hidden
inside it), the fork's bytes have the relocation undone before hashing:
every occurrence of the private prefix becomes the stock one. Anything
still different after that is the fork.

Exit status: 0 if identical, 1 if anything differs, 2 on a usage or
environment error. --allow-delta prints the delta and exits 0, which is
what a fork that has a delta will want once it has one.
"""

import ctypes
import hashlib
import subprocess
import sys

DEFAULT_FORK = "/usr/lib/lisa-desktop/lib/gnome-shell/libshell-18.so"
DEFAULT_STOCK = "/usr/lib/gnome-shell/libshell-18.so"
# The private prefix, and what the same tree looks like at /usr. Undoing
# this substitution turns 'built somewhere else' back into 'the same
# bytes'; see the module docstring.
RELOCATION = (b"/usr/lib/lisa-desktop/lib", b"/usr/lib"), \
             (b"/usr/lib/lisa-desktop/share", b"/usr/share")


def manifest(sofile, unrelocate=False):
    """sha256 of every GResource the given library registers."""
    import gi

    gi.require_version("Gio", "2.0")
    from gi.repository import Gio

    # RTLD_GLOBAL so the library's constructor runs and registers its
    # resource with the GLib in this process.
    ctypes.CDLL(sofile, mode=ctypes.RTLD_GLOBAL)

    out = []

    def walk(path):
        try:
            children = Gio.resources_enumerate_children(path, 0)
        except Exception:
            return
        for child in children:
            if child.endswith("/"):
                walk(path + child)
            else:
                data = Gio.resources_lookup_data(path + child, 0).get_data()
                if unrelocate:
                    for private, stock in RELOCATION:
                        data = data.replace(private, stock)
                digest = hashlib.sha256(data).hexdigest()
                out.append((path + child, digest))

    walk("/")
    return sorted(out)


def manifest_of(sofile, unrelocate=False):
    """One library per process: two libshells in one process would
    register the same resource paths twice and the comparison would be
    meaningless."""
    argv = [sys.executable, __file__, "--manifest", sofile]
    if unrelocate:
        argv.append("--unrelocate")
    proc = subprocess.run(argv, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        sys.exit(f"!! could not read resources from {sofile}")
    entries = {}
    for line in proc.stdout.splitlines():
        digest, path = line.split(" ", 1)
        entries[path] = digest
    return entries


def main(argv):
    if argv[:1] == ["--manifest"]:
        for path, digest in manifest(argv[1], unrelocate="--unrelocate" in argv):
            print(f"{digest} {path}")
        return 0

    allow_delta = False
    if argv[:1] == ["--allow-delta"]:
        allow_delta, argv = True, argv[1:]

    fork = argv[0] if len(argv) > 0 else DEFAULT_FORK
    stock = argv[1] if len(argv) > 1 else DEFAULT_STOCK

    print(f":: fork  {fork}")
    print(f":: stock {stock}")
    print(":: comparing modulo the install prefix "
          f"({RELOCATION[0][0].decode()} -> {RELOCATION[0][1].decode()})")
    ours, theirs = manifest_of(fork, unrelocate=True), manifest_of(stock)
    print(f":: {len(ours)} resources in the fork, {len(theirs)} in stock")

    # Three questions kept separate, because they mean different things:
    # a file we added, a file we removed, a file we edited.
    delta = {
        "added": sorted(set(ours) - set(theirs)),
        "removed": sorted(set(theirs) - set(ours)),
        "changed": sorted(p for p in set(ours) & set(theirs) if ours[p] != theirs[p]),
    }

    if not any(delta.values()):
        print(":: identical — the fork's user interface is byte-for-byte the distribution's")
        return 0

    for kind, paths in delta.items():
        if paths:
            print(f"-- {kind}:")
            for p in paths:
                print(f"   {p}")

    if allow_delta:
        return 0
    print("!! the fork's resources differ from stock; at ADR-0038 step 2 they must not",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
