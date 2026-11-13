#!/bin/sh
# Wait for the current process to exit before opening the rebuilt app bundle.
previous_pid="$1"
app_path="$2"
attempt=0
while kill -0 "$previous_pid" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 150 ]; then exit 1; fi
    sleep 0.1
done
exec /usr/bin/open -n "$app_path"
