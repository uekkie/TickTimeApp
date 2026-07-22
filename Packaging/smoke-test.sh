#!/bin/bash

set -u

app_bundle="${1:?usage: smoke-test.sh /path/to/TickTime.app}"
executable="$app_bundle/Contents/MacOS/TickTime"
log_file="$(mktemp /private/tmp/TickTime-smoke.XXXXXX)"
smoke_directory="$(mktemp -d /private/tmp/TickTime-smoke-app.XXXXXX)"
smoke_executable="$smoke_directory/TickTime"
cp "$executable" "$smoke_executable"

TickTime_DATA_DIRECTORY="$smoke_directory/data" \
    "$smoke_executable" >"$log_file" 2>&1 &
app_pid=$!
sleep 1

if ! jobs -pr | grep -qx "$app_pid"; then
    wait "$app_pid"
    exit_code=$?
    sed -n '1,120p' "$log_file"
    printf 'TickTime exited during launch with status %s\n' "$exit_code" >&2
    exit 1
fi

kill -KILL "$app_pid"
wait "$app_pid" 2>/dev/null || true
printf 'TickTime stayed running through the executable launch window\n'
