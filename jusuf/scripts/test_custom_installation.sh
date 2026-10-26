#!/bin/bash

# Run once inside the Flux instance, as the broker's initial program.
# Usage: bash test_custom_installation.sh [LOG_DIRECTORY] [TIMEOUT_SECONDS]
set -eo pipefail

LOG_DIR="${1:-${CUSTOM_TEST_LOG_DIR:-$PWD/flux-custom-check-${SLURM_JOB_ID:-$$}}}"
WAIT_SECONDS="${2:-${CUSTOM_TEST_TIMEOUT:-60}}"
if [[ ! "$WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Timeout must be a positive integer number of seconds.\n' >&2
    exit 2
fi
mkdir -p "$LOG_DIR"
DEADLINE=$((SECONDS + WAIT_SECONDS))

diagnostics() {
    local status=$?
    trap - EXIT
    if (( status != 0 )); then
        printf '\nCustom Flux check failed. Capturing broker diagnostics in %s\n' "$LOG_DIR" >&2
        flux module list > "$LOG_DIR/modules.txt" 2> "$LOG_DIR/modules.err" || true
        flux config get > "$LOG_DIR/config.json" 2> "$LOG_DIR/config.err" || true
        flux dmesg > "$LOG_DIR/dmesg.log" 2> "$LOG_DIR/dmesg.err" || true
        cat "$LOG_DIR/modules.txt" "$LOG_DIR/dmesg.log" "$LOG_DIR/dmesg.err" >&2
    fi
    exit "$status"
}
trap diagnostics EXIT

printf 'Waiting for Fluxion resource and qmanager modules (timeout %ss)...\n' "$WAIT_SECONDS"
while :; do
    if flux module list > "$LOG_DIR/modules.txt" 2> "$LOG_DIR/modules.err" \
        && awk '$1 == "sched-fluxion-resource" { found = 1 } END { exit !found }' "$LOG_DIR/modules.txt" \
        && awk '$1 == "sched-fluxion-qmanager" { found = 1 } END { exit !found }' "$LOG_DIR/modules.txt"; then
        break
    fi
    if (( SECONDS >= DEADLINE )); then
        printf 'Timed out waiting for Fluxion modules.\n' >&2
        exit 1
    fi
    sleep 1
done
cat "$LOG_DIR/modules.txt"

printf '\nWaiting for the active Argilos configuration...\n'
until flux config get --type=object sched-fluxion-resource.argilos \
    > "$LOG_DIR/argilos-config.json" 2> "$LOG_DIR/argilos-config.err"; do
    if (( SECONDS >= DEADLINE )); then
        printf 'Timed out waiting for sched-fluxion-resource.argilos in broker configuration.\n' >&2
        exit 1
    fi
    sleep 1
done
flux config get > "$LOG_DIR/config.json"
flux config get sched-fluxion-resource.traverser > "$LOG_DIR/traverser.txt"
if [[ "$(cat "$LOG_DIR/traverser.txt")" != flexible_argilos ]]; then
    printf 'Expected traverser=flexible_argilos; got: %s\n' "$(cat "$LOG_DIR/traverser.txt")" >&2
    exit 1
fi
cat "$LOG_DIR/argilos-config.json"

printf '\nWaiting for the scheduler to log the parsed Argilos values...\n'
while :; do
    flux dmesg > "$LOG_DIR/dmesg.log"
    if python3 - "$LOG_DIR/argilos-config.json" "$LOG_DIR/dmesg.log" \
        > "$LOG_DIR/argilos-match.txt" <<'PY'
import json
import math
import re
import sys
from pathlib import Path

# Defaults and log format from scheduler commit 73fe5cc7e3bf52edb73482b0cbb0698dc2b99345.
expected = dict(b=8.0, beta=0.7, k=0.8, load_breakpoint=0.8, delta=0.9, gamma=2.0)
configured = json.loads(Path(sys.argv[1]).read_text())
if (not isinstance(configured, dict) or set(configured) - set(expected)
        or any(isinstance(v, bool) or not isinstance(v, (int, float))
               or not math.isfinite(v) for v in configured.values())):
    sys.exit('Invalid Argilos configuration; see argilos-config.json')
expected.update(configured)

number = r'([-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)'
pattern = r'Argilos config: ' + r'\s+'.join(
    re.escape(key) + '=' + number for key in expected
)
for line in reversed(Path(sys.argv[2]).read_text().splitlines()):
    if 'sched-fluxion-resource' not in line:
        continue
    match = re.search(pattern, line)
    if match and all(math.isclose(float(actual), value, rel_tol=1e-5, abs_tol=1e-12)
                     for actual, value in zip(match.groups(), expected.values())):
        print(line)
        print('PASS: all six logged Argilos values match the active configuration and defaults.')
        sys.exit(0)
sys.exit(1)
PY
    then
        break
    fi
    if (( SECONDS >= DEADLINE )); then
        printf 'Timed out: no Argilos config log matching the active values.\n' >&2
        printf 'Check that the installed scheduler includes commit 73fe5cc7e3bf52edb73482b0cbb0698dc2b99345.\n' >&2
        exit 1
    fi
    sleep 1
done

printf '\nCaptured broker log:\n'
cat "$LOG_DIR/dmesg.log"
printf '\nArgilos configuration verification:\n'
cat "$LOG_DIR/argilos-match.txt"

# Preserve the existing Python CLI plugin check, once per broker instance.
flux run --list-plugins > "$LOG_DIR/cli-plugins.txt"
cat "$LOG_DIR/cli-plugins.txt"
printf '\nPASS: Fluxion modules are loaded and Argilos configuration was parsed. Logs: %s\n' "$LOG_DIR"
