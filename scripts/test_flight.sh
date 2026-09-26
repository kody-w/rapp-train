#!/bin/bash
# Offline regression for the public piped launcher. No real sockets or signals.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLIGHT_SCRIPT="${1:-$ROOT/flight.sh}"
REAL_PYTHON="$(command -v python3)"
TEST_ROOT="$(mktemp -d "$ROOT/.flight-test.XXXXXX")"
trap 'command rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/socket"

# Run the actual Python preflight against a socket double, never the host stack.
cat > "$TEST_ROOT/socket/socket.py" <<'PY'
import errno
import os

AF_INET, AF_INET6, SOCK_STREAM = 2, 10, 1
has_ipv6 = True


class socket:
    def __init__(self, family=AF_INET, type=SOCK_STREAM):
        self.family = family
        if family == AF_INET6 and os.environ["SCENARIO"] == "ipv6-disabled":
            raise OSError(errno.EAFNOSUPPORT, "IPv6 disabled")

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def bind(self, address):
        host, port = address
        assert host == ("0.0.0.0" if self.family == AF_INET else "::")
        assert port == int(os.environ["FLIGHT_PORT"])
        with open(os.environ["CASE_DIR"] + "/trace", "a") as trace:
            trace.write("probe %s %s\n" % (self.family, port))
        scenario = os.environ["SCENARIO"]
        if ((scenario == "occupied" and self.family == AF_INET)
                or (scenario == "occupied-v6" and self.family == AF_INET6)):
            raise OSError(errno.EADDRINUSE, "Address already in use")
        if scenario == "port-denied":
            raise OSError(errno.EACCES, "Permission denied")
PY

# This short-lived shim only writes fixtures. Liveness is supplied by kill().
cat > "$TEST_ROOT/bin/nohup" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'launch %s %s %s\n' "$HOME" "$PORT" "$*" >> "$CASE_DIR/trace"
printf '%s\n' "$$" > "$CASE_DIR/launched.pid"
for line in 1 2 3 4 5 6 7; do echo "startup log $line"; done
echo "startup log 8: synthetic server result"
: > "$CASE_DIR/launched"
SH
cat > "$TEST_ROOT/bin/python" <<'SH'
#!/bin/bash
set -euo pipefail
printf 'pip %s\n' "$*" >> "$CASE_DIR/trace"
[[ "$*" == "-m pip install --quiet -r "* ]]
SH
chmod +x "$TEST_ROOT/bin/nohup" "$TEST_ROOT/bin/python"

trace() { printf '%s\n' "$*" >> "$CASE_DIR/trace"; }
git() {
    trace "git $*"
    case "$1" in
        clone)
            mkdir -p "${8}/.ring/tools"
            : > "${8}/.ring/tools/render_ring.py"
            ;;
        -C) echo abc1234 ;;
        *) echo "unexpected git command: $*" >&2; exit 97 ;;
    esac
}
# Exported stubs run inside flight.sh, which assigns FLIGHT_HOME.
# shellcheck disable=SC2153
python3() {
    trace "python3 $*"
    if [ "$1" = "-" ]; then
        FLIGHT_PORT="$FLIGHT_PORT" PYTHONPATH="$TEST_ROOT/socket" "$REAL_PYTHON" -S "$@"
    elif [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
        mkdir -p "$3/bin"
        ln -s "$TEST_ROOT/bin/python" "$3/bin/python"
    elif [ "$1" = "$FLIGHT_HOME/src/.ring/tools/render_ring.py" ]; then
        mkdir -p "$FLIGHT_HOME/render/rapp_brainstem"
        : > "$FLIGHT_HOME/render/rapp_brainstem/requirements.txt"
    else
        echo "unexpected python3 command: $*" >&2; exit 97
    fi
}
curl() {
    trace "curl $*"
    if [ "$*" != "-fsS http://localhost:$FLIGHT_PORT/health" ]; then
        echo "unexpected curl command: $*" >&2; exit 97
    fi
    [ "$SCENARIO" != "timeout" ] || return 22
    case "$SCENARIO" in
        exits-during-health) : > "$CASE_DIR/dead" ;;
        exits-during-failed-health) : > "$CASE_DIR/dead"; return 22 ;;
        pidfile-replaced)
            echo 999999 > "$FLIGHT_HOME/flight.pid"
            : > "$CASE_DIR/dead"
            ;;
    esac
    echo '{"ok":true}'
}
kill() {
    trace "kill $*"
    if [ "$*" = "-0 999999" ] || [ "$*" = "999999" ]; then
        return 0
    fi
    if [ "$#" != 2 ] || [ "$1" != "-0" ] ||
        [ "$2" != "$(cat "$CASE_DIR/launched.pid")" ]; then
        echo "unexpected signal or PID: $*" >&2; exit 97
    fi
    case "$SCENARIO" in occupied|occupied-v6|bind-death) return 1 ;; esac
    [ ! -f "$CASE_DIR/dead" ]
}
sleep() {
    trace "sleep $*"
    [ "$(cat "$FLIGHT_HOME/flight.pid")" != 999999 ] || return 0
    # Synchronize with the fixture writer, not wall-clock server startup.
    local _
    for _ in $(seq 1 200); do
        [ ! -f "$CASE_DIR/launched" ] || return 0
        command sleep 0.01
    done
    echo "launch fixture did not complete" >&2; exit 97
}
rm() {
    trace "rm $*"
    if [ "$#" != 3 ] || [ "$1" != "-rf" ] ||
        [ "$2" != "$FLIGHT_HOME/src" ] || [ "$3" != "$FLIGHT_HOME/render" ]; then
        echo "unexpected deletion: $*" >&2; exit 97
    fi
    command rm "$@"
}
tail() {
    trace "tail $*"
    if [ "$#" != 2 ] || [ "$1" != "-5" ] || [ "$2" != "$FLIGHT_HOME/flight.log" ]; then
        echo "unexpected log tail: $*" >&2; exit 97
    fi
    command tail "$@"
}
export -f trace git python3 curl kill sleep rm tail
export REAL_PYTHON TEST_ROOT

expect_contains() {
    if ! grep -Fq -- "$2" "$1"; then
        echo "  missing: $2"; return 1
    fi
}
expect_absent() {
    if grep -Eq -- "$2" "$1"; then
        echo "  unexpected: $2"; return 1
    fi
}
expect_equal() {
    if [ "$1" != "$2" ]; then
        echo "  $3: expected $2, got $1"; return 1
    fi
}

failures=0
cases=0
run_case() {
    local scenario="$1" ring="${2:-canary}" branch="${3:-main}"
    local port="${4:-8123}" slug="$ring" status failed=0 expected=1 pid checks
    [ "$branch" = main ] || slug="$ring-$(echo "$branch" | tr '/' '-')"
    local case_dir="$TEST_ROOT/$scenario-$slug-$port"
    local flight_home="$case_dir/home/.rapp-flight/$slug"
    local output="$case_dir/output" events="$case_dir/trace"
    mkdir -p "$flight_home/src" "$flight_home/render"
    : > "$events"
    : > "$flight_home/src/preserve"
    : > "$flight_home/render/preserve"
    case "$scenario" in
        occupied|occupied-v6|port-denied|invalid-port) echo 999999 > "$flight_home/flight.pid" ;;
        healthy|default-port|ipv6-disabled) expected=0 ;;
        invalid-ring|invalid-branch) expected=2 ;;
    esac
    if (
        export HOME="$case_dir/home" FLIGHT_PORT="$port" PATH="$TEST_ROOT/bin:$PATH"
        export SCENARIO="$scenario" CASE_DIR="$case_dir" BASH_ENV=/dev/null
        if [ "$scenario" = default-port ]; then unset FLIGHT_PORT; fi
        # Same bash -s shape as the public one-liner, with all I/O stubbed.
        cat "$FLIGHT_SCRIPT" | bash -s -- "$ring" "$branch"
    ) > "$output" 2>&1; then
        status=0
    else
        status=$?
    fi
    expect_equal "$status" "$expected" "exit status" || failed=1
    if [ "$expected" != 0 ]; then
        expect_absent "$output" "is flying:" || failed=1
    fi
    case "$scenario" in
        occupied|occupied-v6|port-denied|invalid-port)
            expect_contains "$output" "port $port" || failed=1
            expect_contains "$output" "FLIGHT_PORT" || failed=1
            expect_absent "$events" "^(kill|rm|git|pip|launch|curl|sleep|tail) " || failed=1
            expect_equal "$(cat "$flight_home/flight.pid")" 999999 "existing pidfile" || failed=1
            [ -f "$flight_home/src/preserve" ] && [ -f "$flight_home/render/preserve" ] || {
                echo "  existing flight files were removed"; failed=1;
            }
            ;;
        invalid-ring|invalid-branch)
            expect_equal "$(cat "$events")" "" "commands before argument validation" || failed=1
            ;;
        *)
            pid="$(cat "$case_dir/launched.pid")"
            if [ "$scenario" = pidfile-replaced ]; then
                expect_equal "$(cat "$flight_home/flight.pid")" 999999 "replaced pidfile" || failed=1
            else
                expect_equal "$(cat "$flight_home/flight.pid")" "$pid" "launched PID" || failed=1
            fi
            expect_contains "$events" "kill -0 $pid" || failed=1
            expect_contains "$events" "probe 2 $port" || failed=1
            expect_contains "$events" "git clone --quiet --depth 1 --branch $branch https://github.com/kody-w/rapp-$ring.git $flight_home/src" || failed=1
            expect_contains "$events" "launch $flight_home $port $flight_home/venv/bin/python brainstem.py" || failed=1
            case "$scenario" in
                bind-death|exits-during-health|exits-during-failed-health|pidfile-replaced)
                    expect_contains "$output" "exited during startup" || failed=1
                    expect_equal "$(grep -c '^sleep ' "$events")" 1 "startup polls" || failed=1
                    if [ "$scenario" = bind-death ]; then
                        expect_absent "$events" "^curl " || failed=1
                    else
                        expect_equal "$(grep -c '^curl ' "$events")" 1 "health requests" || failed=1
                    fi
                    ;;
                timeout)
                    expect_contains "$output" "did not answer /health in 20s" || failed=1
                    expect_equal "$(grep -c '^curl ' "$events")" 20 "health requests" || failed=1
                    expect_equal "$(grep -c '^sleep ' "$events")" 20 "startup polls" || failed=1
                    ;;
                healthy|default-port|ipv6-disabled)
                    expect_contains "$output" "$ring@abc1234 is flying: http://localhost:$port" || failed=1
                    expect_contains "$output" "auth (optional): open the UI and use Login" || failed=1
                    expect_contains "$output" "GitHub device flow" || failed=1
                    expect_contains "$output" "stop:  kill \$(cat $flight_home/flight.pid)" || failed=1
                    expect_contains "$output" "wipe:  rm -rf $flight_home" || failed=1
                    checks="$(grep -c "^kill -0 $pid$" "$events" || [ "$?" = 1 ])"
                    [ "$checks" -ge 2 ] || { echo "  PID not checked around health"; failed=1; }
                    expect_absent "$events" "^tail " || failed=1
                    ;;
            esac
            if [ "$expected" = 1 ]; then
                expect_contains "$events" "tail -5 $flight_home/flight.log" || failed=1
                expect_absent "$output" "startup log [123]$" || failed=1
                expect_equal "$(grep -c '^startup log ' "$output")" 5 "log tail lines" || failed=1
            fi
            ;;
    esac
    cases=$((cases + 1))
    if [ "$failed" = 0 ]; then
        echo "PASS $scenario ($ring@$branch, port $port)"
    else
        echo "FAIL $scenario ($ring@$branch, port $port)"
        command tail -12 "$output"
        failures=$((failures + 1))
    fi
}

run_case occupied
run_case occupied-v6
run_case port-denied
run_case invalid-port canary main 0
run_case invalid-port canary main 65536
run_case invalid-port canary main not-a-port
run_case bind-death
run_case exits-during-health
run_case exits-during-failed-health
run_case pidfile-replaced
run_case default-port canary main 7075
run_case healthy nightly
run_case healthy alpha
run_case healthy beta
run_case healthy canary fix/streaming
run_case ipv6-disabled
run_case timeout
run_case invalid-ring unknown
run_case invalid-branch beta fix/streaming
if [ "$failures" != 0 ]; then
    echo "$failures flight regression case(s) failed" >&2
    exit 1
fi
echo "All $cases offline flight regression cases passed."
