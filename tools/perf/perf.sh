#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 1
fi

cmd=("$@")
cmd_name="$(basename "${cmd[0]}")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warmup="${PERF_WARMUP:-10}"
duration="${PERF_DURATION:-60}"
grace="${PERF_GRACE:-5}"

echo "== perf run (${cmd_name}) [rss-only] =="

app_pid=""
"${cmd[@]}" &
app_pid=$!

if [ -d "/proc/${app_pid}" ]; then
  samples=0
  ticks=0
  rss_sum=0
  rss_min=0
  rss_max=0
  cpu_sum=0
  cpu_max=0
  anon_sum=0
  file_sum=0
  shmem_sum=0
  total=$((warmup + duration))
  for _ in $(seq 1 "${total}"); do
    if [ ! -d "/proc/${app_pid}" ]; then
      break
    fi
    read -r rss_kb etime cpu_pct <<EOF
$(ps -p "${app_pid}" -o rss=,etime=,%cpu=)
EOF
    read -r rss_anon_kb rss_file_kb rss_shmem_kb <<EOF
$(awk '/RssAnon|RssFile|RssShmem/ {print $2}' /proc/"${app_pid}"/status | tr '\n' ' ')
EOF

    ticks=$((ticks + 1))
    if [ "${ticks}" -le "${warmup}" ]; then
      sleep 1
      continue
    fi

    samples=$((samples + 1))
    rss_sum=$((rss_sum + rss_kb))
    anon_sum=$((anon_sum + rss_anon_kb))
    file_sum=$((file_sum + rss_file_kb))
    shmem_sum=$((shmem_sum + rss_shmem_kb))
    if [ "${samples}" -eq 1 ] || [ "${rss_kb}" -lt "${rss_min}" ]; then rss_min="${rss_kb}"; fi
    if [ "${rss_kb}" -gt "${rss_max}" ]; then rss_max="${rss_kb}"; fi
    cpu_int=$(awk "BEGIN {printf \"%d\", ${cpu_pct}+0.5}")
    cpu_sum=$((cpu_sum + cpu_int))
    if [ "${cpu_int}" -gt "${cpu_max}" ]; then cpu_max="${cpu_int}"; fi
    sleep 1
  done

  if [ "${samples}" -gt 0 ]; then
    rss_avg_mb=$(awk "BEGIN {printf \"%.1f\", (${rss_sum}/${samples})/1024}")
    rss_min_mb=$(awk "BEGIN {printf \"%.1f\", ${rss_min}/1024}")
    rss_max_mb=$(awk "BEGIN {printf \"%.1f\", ${rss_max}/1024}")
    anon_avg_mb=$(awk "BEGIN {printf \"%.1f\", (${anon_sum}/${samples})/1024}")
    file_avg_mb=$(awk "BEGIN {printf \"%.1f\", (${file_sum}/${samples})/1024}")
    shmem_avg_mb=$(awk "BEGIN {printf \"%.1f\", (${shmem_sum}/${samples})/1024}")
    cpu_avg=$(awk "BEGIN {printf \"%.1f\", ${cpu_sum}/${samples}}")
    echo "== rss summary =="
    echo "rss_avg=${rss_avg_mb}MB rss_min=${rss_min_mb}MB rss_max=${rss_max_mb}MB cpu_avg=${cpu_avg}% cpu_max=${cpu_max}% anon_avg=${anon_avg_mb}MB file_avg=${file_avg_mb}MB shmem_avg=${shmem_avg_mb}MB"
    echo "== rss window =="
    echo "warmup=${warmup}s duration=${duration}s samples=${samples}"

    rss_limit_mb=""
    cpu_limit_pct=""
    case "${cmd_name}" in
      nizam-panel) rss_limit_mb=50; cpu_limit_pct=1.0 ;;
      nizam-dock) rss_limit_mb=35; cpu_limit_pct=0.2 ;;
      nizam-terminal)
        terminal_profile="${PERF_TERMINAL_PROFILE:-idle}"
        if [ "$terminal_profile" = "burst" ]; then
          rss_limit_mb=130; cpu_limit_pct=4
        else
          rss_limit_mb=90; cpu_limit_pct=1.0
        fi
        echo "== terminal scenario =="
        echo "profile=${terminal_profile} tabs=1 output=none"
        ;;
    esac

    if [ -n "${rss_limit_mb}" ]; then
      rss_fail=$(awk "BEGIN {print (${rss_avg_mb} > ${rss_limit_mb}) ? 1 : 0}")
      cpu_fail=$(awk "BEGIN {print (${cpu_avg} > ${cpu_limit_pct}) ? 1 : 0}")
      if [ "${rss_fail}" -eq 1 ] || [ "${cpu_fail}" -eq 1 ]; then
        if [ "${PERF_GUARDRAIL_SOFT:-1}" = "1" ]; then
          echo "== perf guardrail WARNING =="
          echo "limit rss_avg<=${rss_limit_mb}MB cpu_avg<=${cpu_limit_pct}%"
          echo "actual rss_avg=${rss_avg_mb}MB cpu_avg=${cpu_avg}%"
        else
          echo "== perf guardrail FAILED =="
          echo "limit rss_avg<=${rss_limit_mb}MB cpu_avg<=${cpu_limit_pct}%"
          echo "actual rss_avg=${rss_avg_mb}MB cpu_avg=${cpu_avg}%"
          exit 2
        fi
      else
        echo "== perf guardrail OK =="
      fi
    fi
  fi
else
  echo "== rss summary (skipped: app exited early) =="
fi

kill -TERM "$app_pid" 2>/dev/null || true
for _ in $(seq 1 "${grace}"); do
  if [ ! -d "/proc/${app_pid}" ]; then
    break
  fi
  sleep 1
done
kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true

echo "== perf run (${cmd_name}) [valgrind] =="
tmp_log="$(mktemp -t nizam-perf.XXXXXX)"
trap 'rm -f "$tmp_log"' EXIT

if [ "${cmd_name}" = "nizam-dock" ]; then
  mkdir -p perf-logs
  export VALGRIND_OPTS="--tool=memcheck --leak-check=summary --show-leak-kinds=definite,indirect --track-origins=yes --errors-for-leak-kinds=definite,indirect --num-callers=25 --error-limit=no --suppressions=${script_dir}/valgrind.supp"
  export VALGRIND_LOG="perf-logs/valgrind-nizam-dock.log"
else
  export VALGRIND_OPTS="--leak-check=summary --show-leak-kinds=definite --errors-for-leak-kinds=definite --track-fds=no --track-origins=no --num-callers=5 --error-limit=no"
  export VALGRIND_LOG="/dev/stdout"
fi

tools/perf/valgrind_run.sh "${cmd[@]}" >"$tmp_log" 2>&1 &
vg_pid=$!

child_pid=""
for _ in $(seq 1 20); do
  child_pid="$(pgrep -P "$vg_pid" | head -n 1 || true)"
  if [ -n "${child_pid}" ]; then
    break
  fi
  sleep 0.1
done

if [ -z "${child_pid}" ]; then
  base="$(basename "${cmd[0]}")"
  child_pid="$(pidof -s "$base" 2>/dev/null || true)"
fi

sleep "${duration}"

term_target="$vg_pid"
if [ -n "${child_pid}" ] && [ "${child_pid}" != "${vg_pid}" ]; then
  term_target="$child_pid"
fi
kill -TERM "$term_target" 2>/dev/null || true

for _ in $(seq 1 "${grace}"); do
  if [ ! -d "/proc/${vg_pid}" ]; then
    break
  fi
  sleep 1
done

kill "$vg_pid" 2>/dev/null || true
wait "$vg_pid" 2>/dev/null || true

if [ "${cmd_name}" = "nizam-dock" ]; then
  dock_log="perf-logs/valgrind-nizam-dock.log"
  if [ -f "$dock_log" ]; then
    err_line="$(awk '/ERROR SUMMARY:/ {sub(/^==[0-9]+== /, ""); print; exit}' "$dock_log")"
    echo "[valgrind] ${err_line}"
    echo "[valgrind] log=${dock_log}"
    if [ "${PERF_KEEP_LOGS:-0}" != "1" ]; then
      rm -f "$dock_log"
      rmdir --ignore-fail-on-non-empty perf-logs 2>/dev/null || true
    fi
  else
    echo "[valgrind] ERROR SUMMARY: log not found"
  fi
  exit 0
fi

awk -v name="$cmd_name" '
  function fmt_bytes_line(line,    n, out) {
    if (match(line, /([0-9,]+) bytes/, m)) {
      n = m[1]; gsub(/,/, "", n);
      if (n >= 1048576) out = sprintf("%.2f MB", n/1048576);
      else if (n >= 1024) out = sprintf("%.1f KB", n/1024);
      else out = sprintf("%d B", n);
      sub(/[0-9,]+ bytes/, out, line);
    }
    return line;
  }
  /^==[0-9]+== / {sub(/^==[0-9]+== /, "");}
  /LEAK SUMMARY:/ {in_leak=1; delete leak; leak_n=0; next}
  in_leak {
    if ($0 ~ /^Rerun with/ || $0 ~ /^For lists/ || $0 ~ /^$/) {in_leak=0; next}
    if ($0 ~ /reachable via heuristic/) {next}
    leak[++leak_n] = fmt_bytes_line($0);
    next
  }
  /ERROR SUMMARY:/ {err = $0; next}
  END {
    if (leak_n == 0 && err == "") exit;
    print "== " name " ==";
    line = "[valgrind] leaks:";
    for (i=1; i<=leak_n; i++) {
      gsub(/^[[:space:]]+/, "", leak[i]);
      if (i == 1) line = line " " leak[i];
      else line = line " | " leak[i];
    }
    print line;
    if (err != "") print "[valgrind] " err;
  }
' "$tmp_log"
