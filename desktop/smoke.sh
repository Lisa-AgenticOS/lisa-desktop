#!/usr/bin/env bash
# Prove that Lisa Desktop boots.
#
#   desktop/smoke.sh [expected-gnome-shell-version]
#
# Starts the forked shell as a headless display server on a private
# session bus and then asks it, over D-Bus, what it is. That is a real
# boot: the binary started, mutter brought up a compositor, the embedded
# JavaScript ran all the way through init.js, and the shell reached the
# point of owning org.gnome.Shell and answering property reads. A shell
# that fails any of that never answers.
#
# It touches nothing outside a temporary directory and a private bus —
# no seat, no login session, no display. It is therefore safe to run on
# a machine somebody is using, which matters, because Lisa has one
# reference device and it has to stay bootable.
#
# Env:
#   LISA_DESKTOP_BIN        the shell binary to boot (default
#                           /usr/bin/gnome-shell -- Lisa Desktop
#                           replaces gnome-shell, so that path is ours)
#   LISA_SMOKE_MOCK_LOGIND  1 to stand up a private system bus with a
#                           mock logind. Needed in a container, which
#                           has no systemd-logind; the shell asks it for
#                           the session at startup and dies without it.
#                           Never set this on a real machine — there the
#                           real logind is the thing being exercised.
#   LISA_SMOKE_ARGS         extra arguments for the shell
#   LISA_SMOKE_TIMEOUT      seconds to wait for the bus name (default 60)
#   LISA_SMOKE_GATE_PROBE   a gdbus-compatible binary installed at the
#                           authorised path (a root-owned regular file
#                           directly inside /usr/lib/lisa/bin). Set it
#                           and the screenshot gate's POSITIVE control
#                           runs; leave it unset and only the negative
#                           control does. Nothing here can grant the
#                           capability — the gate is compiled into the
#                           shell and reads the caller's /proc entry —
#                           this only tells the harness what to run.
#   LISA_SMOKE_GATE_PROBE_UNOWNED
#                           the same binary at the same directory but
#                           NOT owned by root. Must be refused.
set -euo pipefail

bin=${LISA_DESKTOP_BIN:-/usr/bin/gnome-shell}
want_version=${1:-}
timeout=${LISA_SMOKE_TIMEOUT:-60}

if [ "${1:-}" = "--inner" ]; then
    # Inside dbus-run-session: a private session bus exists.
    log=$LISA_SMOKE_LOG
    # shellcheck disable=SC2086  # LISA_SMOKE_ARGS is a word list on purpose
    # Append, never truncate: the caller is writing its own stderr to
    # the same file, and a truncation here erases the evidence of
    # whatever went wrong before the shell even started.
    "$LISA_SMOKE_BIN" --headless --virtual-monitor 1280x720 --mode=user \
        ${LISA_SMOKE_ARGS:-} >>"$log" 2>&1 &
    shell_pid=$!

    prop() {
        gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
            --method org.freedesktop.DBus.Properties.Get org.gnome.Shell "$1" \
            2>/dev/null | sed -e "s/^(<'//" -e "s/'>,)$//"
    }

    # Wait on the property read, not on the bus name. The shell takes
    # the name before it exports /org/gnome/Shell, so a name-owner check
    # returns true a beat too early and the read that follows fails with
    # "Object does not exist" — a passing shell reported as a failure.
    ok=
    for _ in $(seq 1 "$LISA_SMOKE_TIMEOUT"); do
        if ! kill -0 "$shell_pid" 2>/dev/null; then
            echo "!! the shell exited before it answered" >&2
            break
        fi
        # `|| true`: until the object is exported gdbus exits non-zero,
        # and under `set -e` a bare assignment from a failing command
        # substitution ends the script — silently, with the shell still
        # starting up. That is a harness bug that reads exactly like a
        # broken shell, which is the worst kind.
        version=$(prop ShellVersion || true)
        if [ -n "$version" ]; then ok=1; break; fi
        sleep 1
    done

    if [ -z "$ok" ]; then
        echo "!! org.gnome.Shell never answered a property read" >&2
        kill "$shell_pid" 2>/dev/null || true
        exit 1
    fi

    printf 'ShellVersion=%s\n' "$version"
    printf 'Mode=%s\n' "$(prop Mode || true)"

    # --- The screenshot gate (lisa-os#266) -----------------------------
    # Lisa Desktop grants org.gnome.Shell.Screenshot to its own
    # root-owned system binaries and to nothing else. Both halves are
    # asserted here, because a gate is only meaningful when the two
    # controls use the SAME program at two different paths: the variable
    # under test is then the authorisation, not the caller's behaviour.
    gate=0
    shoot() {  # shoot <binary> <output-png>
        "$1" call --session \
            --dest org.gnome.Shell.Screenshot \
            --object-path /org/gnome/Shell/Screenshot \
            --method org.gnome.Shell.Screenshot.Screenshot \
            false false "$2" 2>&1
    }

    # Negative control. This harness's gdbus is not Lisa system tooling,
    # so the capture must be refused and no file may appear. Free, safe
    # on any machine, and it runs unconditionally: without it a green
    # positive control would only prove that screenshots work.
    deny_png=$XDG_RUNTIME_DIR/gate-denied.png
    deny_out=$(shoot "$(command -v gdbus)" "$deny_png" || true)
    printf 'GateDenied=%s\n' "$deny_out"
    case "$deny_out" in
        *AccessDenied*) ;;
        *) echo "!! an unauthorised caller was NOT refused: $deny_out"; gate=1 ;;
    esac
    if [ -e "$deny_png" ]; then
        echo "!! the refused call still produced $deny_png"; gate=1
    fi

    # Ownership control, when CI provides it: the authorised DIRECTORY
    # with a binary root does not own. Refused, or the uid-0 check is
    # decorative.
    if [ -n "${LISA_SMOKE_GATE_PROBE_UNOWNED:-}" ]; then
        unowned_png=$XDG_RUNTIME_DIR/gate-unowned.png
        unowned_out=$(shoot "$LISA_SMOKE_GATE_PROBE_UNOWNED" "$unowned_png" || true)
        printf 'GateUnowned=%s\n' "$unowned_out"
        case "$unowned_out" in
            *AccessDenied*) ;;
            *) echo "!! a non-root-owned binary in the authorised directory was allowed"; gate=1 ;;
        esac
    fi

    # Positive control. Without it the negative control above is
    # satisfied by a gate that refuses everybody, which is what stock
    # GNOME already does and is not the thing being added.
    if [ -n "${LISA_SMOKE_GATE_PROBE:-}" ]; then
        allow_png=$XDG_RUNTIME_DIR/gate-allowed.png
        allow_out=$(shoot "$LISA_SMOKE_GATE_PROBE" "$allow_png" || true)
        printf 'GateAllowed=%s\n' "$allow_out"
        case "$allow_out" in
            *"(true,"*) ;;
            *) echo "!! the authorised caller was refused: $allow_out"; gate=1 ;;
        esac
        # A capture that returns success and writes nothing readable is
        # the failure this whole issue is about, so check the pixels.
        if [ ! -s "$allow_png" ]; then
            echo "!! the authorised capture produced no file at $allow_png"; gate=1
        else
            printf 'GateAllowedBytes=%s\n' "$(wc -c <"$allow_png" | tr -d ' ')"
            head -c 8 "$allow_png" | od -An -tx1 | tr -d ' \n' > "$XDG_RUNTIME_DIR/magic"
            if [ "$(cat "$XDG_RUNTIME_DIR/magic")" != "89504e470d0a1a0a" ]; then
                echo "!! the authorised capture is not a PNG"; gate=1
            fi
        fi
    else
        printf 'GateAllowed=%s\n' "skipped (LISA_SMOKE_GATE_PROBE unset)"
    fi

    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
    exit "$gate"
fi

[ -x "$bin" ] || { echo "!! no shell binary at $bin" >&2; exit 1; }

for tool in dbus-run-session gdbus; do
    command -v "$tool" >/dev/null || { echo "!! $tool is not installed" >&2; exit 1; }
done

run=$(mktemp -d)
chmod 700 "$run"
mock_pid=
cleanup() { [ -n "$mock_pid" ] && kill "$mock_pid" 2>/dev/null; rm -rf "$run"; }
trap cleanup EXIT

log="$run/shell.log"
out="$run/props"

if [ "${LISA_SMOKE_MOCK_LOGIND:-}" = 1 ]; then
    # A container has no systemd-logind, and GNOME Shell asks logind for
    # the session while building the LayoutManager — it dies there, in
    # JavaScript, long before it would own a bus name. So CI gets a
    # private system bus with python-dbusmock's logind template.
    #
    # This is a prop for the environment, not for the thing under test:
    # the shell binary, the compositor and every line of JavaScript are
    # the real ones. What it does not prove is anything about session
    # registration, and this script does not claim to.
    command -v dbus-daemon >/dev/null || { echo "!! dbus-daemon is not installed" >&2; exit 1; }
    python -c 'import dbusmock' 2>/dev/null || { echo "!! python-dbusmock is not installed" >&2; exit 1; }
    cat > "$run/system.conf" <<XML
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:tmpdir=$run</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_type="method_call"/>
    <allow send_type="signal"/>
    <allow send_type="method_return"/>
    <allow send_type="error"/>
    <allow receive_type="method_call"/>
    <allow receive_type="signal"/>
    <allow receive_type="method_return"/>
    <allow receive_type="error"/>
  </policy>
</busconfig>
XML
    bus_out=$(dbus-daemon --config-file="$run/system.conf" --print-address=1 --print-pid=1 --fork)
    DBUS_SYSTEM_BUS_ADDRESS=$(printf '%s\n' "$bus_out" | head -1)
    mock_pid=$(printf '%s\n' "$bus_out" | tail -1)
    export DBUS_SYSTEM_BUS_ADDRESS
    python -m dbusmock --system --template logind >"$run/logind.log" 2>&1 &
    for _ in $(seq 1 20); do
        gdbus call --system --dest org.freedesktop.login1 \
            --object-path /org/freedesktop/login1 \
            --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 && break
        sleep 1
    done
    echo ":: mock logind on a private system bus"
fi

echo ":: booting $bin (headless, private bus)"
set +e
XDG_RUNTIME_DIR="$run" \
XDG_SESSION_TYPE=wayland \
XDG_CURRENT_DESKTOP=GNOME \
LISA_SMOKE_BIN="$bin" \
LISA_SMOKE_LOG="$log" \
LISA_SMOKE_ARGS="${LISA_SMOKE_ARGS:-}" \
LISA_SMOKE_TIMEOUT="$timeout" \
    dbus-run-session -- bash "$0" --inner >"$out" 2>>"$log"
rc=$?
set -e

# Never `grep -q` a pipe from the thing under test and then report the
# grep's exit status: write what happened to a file and print the file.
if [ $rc -ne 0 ]; then
    # Either the shell never answered, or it answered and a check below
    # it failed. The harness output says which — it prints ShellVersion
    # before it touches anything else.
    echo "!! Lisa Desktop's boot check failed"
    echo "---- harness ----"; cat "$out"
    echo "---- shell log ----"; cat "$log" 2>/dev/null
    exit 1
fi

cat "$out"

got_version=$(sed -n 's/^ShellVersion=//p' "$out")
got_mode=$(sed -n 's/^Mode=//p' "$out")

fail=0
if [ -n "$want_version" ] && [ "$got_version" != "$want_version" ]; then
    echo "!! ShellVersion is '$got_version', expected '$want_version'" >&2
    fail=1
fi
if [ "$got_mode" != "user" ]; then
    echo "!! Mode is '$got_mode', expected 'user'" >&2
    fail=1
fi
if [ $fail -ne 0 ]; then
    echo "---- shell log ----"; cat "$log" 2>/dev/null
    exit 1
fi

echo ":: Lisa Desktop booted, owned org.gnome.Shell, and reported ${got_version:-<unread>} in mode $got_mode"
echo ":: the screenshot gate refused an unauthorised caller$(
    grep -q '^GateAllowedBytes=' "$out" && echo ' and served an authorised one' || true)"
