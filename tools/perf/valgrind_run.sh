#!/usr/bin/env bash
set -euo pipefail

if ! command -v valgrind >/dev/null 2>&1; then
  echo "valgrind not found in PATH" >&2
  exit 1
fi

log="${VALGRIND_LOG:-/tmp/nizam-valgrind.%p.log}"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 1
fi

VALGRIND_OPTS="${VALGRIND_OPTS:-}"
if [ -n "$VALGRIND_OPTS" ]; then
  opts="$VALGRIND_OPTS"
else
  opts="--leak-check=full --show-leak-kinds=definite,indirect --track-origins=yes --num-callers=30 --time-stamp=yes --track-fds=yes"
fi

runner=(valgrind $opts --log-file="$log")

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  if command -v xvfb-run >/dev/null 2>&1; then
    exec xvfb-run -a -s "-screen 0 1024x768x24" "${runner[@]}" "$@"
  else
    echo "no DISPLAY/WAYLAND_DISPLAY and xvfb-run not found; GUI apps cannot run under valgrind" >&2
    exit 1
  fi
fi

if [ "${VALGRIND_FILTER:-}" = "1" ]; then
  "${runner[@]}" "$@" 2>&1 | awk '
    /Command:/ {print; next}
    /HEAP SUMMARY:/ {print; in_block=1; next}
    in_block {print}
    /ERROR SUMMARY:/ {in_block=0}
  '
  exit $?
fi

exec "${runner[@]}" "$@"
