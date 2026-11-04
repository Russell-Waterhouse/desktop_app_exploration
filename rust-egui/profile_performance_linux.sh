#!/usr/bin/env bash
# Performance metrics for rust-egui on Linux, into a CSV in
# this folder. Run it from anywhere; it cds to its own folder
# first, like build_linux.sh, so the builds, binaries, and CSV
# are always this stack's.
#
# What it measures, in one row per run:
#   compile time, clean and cached, for debug AND release
#   binary size, debug and release
#   memory, peak and average PSS, debug and release
#   CPU, peak and average percent, debug and release
#
# Usage:
#   ./profile_performance_linux.sh [--output FILE]
#                                  [--duration SECONDS]
#                                  [--interval SECONDS]
#                                  [--jobs N]
#
#   --output FILE       CSV file. Default: performance_metrics.csv
#                       in this folder. The file is appended to;
#                       the header is written only if the file
#                       does not already have content, so repeated
#                       runs accumulate comparable rows
#                       (distinguished by timestamp).
#   --duration SECONDS  How long each runtime run is held.
#                       Default: 10.
#   --interval SECONDS  Time between runtime samples. Default: 1.
#                       Fractional values (e.g. 0.5) are allowed.
#   --jobs N            Parallelism for the builds. Default: nproc.
#
# Output columns:
#   timestamp,stack,
#   compile_time_clean_debug_seconds,
#   compile_time_cached_debug_seconds,
#   compile_time_clean_release_seconds,
#   compile_time_cached_release_seconds,
#   binary_size_debug_bytes,binary_size_release_bytes,
#   memory_peak_debug_kb,memory_average_debug_kb,
#   memory_peak_release_kb,memory_average_release_kb,
#   cpu_peak_debug_percent,cpu_average_debug_percent,
#   cpu_peak_release_percent,cpu_average_release_percent
#
# Definitions, so runs are comparable across stacks:
#   compile time     Wall-clock time for the cargo build
#                    command, to the millisecond, exactly as
#                    profile_build_times_linux.sh measures it.
#                    "clean" runs `cargo clean` first (target/
#                    only; the cargo registry cache is kept, so
#                    dependencies are rebuilt, not re-downloaded).
#                    "cached" runs the same command again with
#                    no clean and no source changes in between.
#   binary size      File size in bytes (stat) of the built
#                    binary, after the cached build. No
#                    stripping is done: this is the binary
#                    cargo produces with the project's default
#                    debug/release profiles.
#   memory           PSS (Proportional Set Size) in kB, summed
#                    over every mapping in /proc/<pid>/smaps,
#                    as in profile_memory_linux.sh. PSS splits
#                    shared pages proportionally between the
#                    processes sharing them, so it is the
#                    fairest single memory number for a GUI app
#                    that shares system libraries. "peak" is
#                    the largest sample, "average" is the mean
#                    of the samples.
#   CPU              Percent, from /proc/<pid>/stat user +
#                    system time (all threads of the process)
#                    divided by wall time over each sample
#                    interval, times 100. On a multi-core
#                    machine this can exceed 100: a process
#                    using two cores fully for an interval
#                    reads about 200. "peak" is the largest
#                    interval, "average" is the mean of the
#                    intervals.
#   cores_used       Not a column here: the build parallelism
#                    is --jobs (nproc by default), and times
#                    from machines with different core counts
#                    are only comparable with that in mind.
#
# Runtime workload: each binary is launched under its own
# Xvfb display, from a fresh temporary working directory, so
# it seeds a fresh recipes.db there and never touches this
# folder's recipes.db. It is held idle for --duration seconds
# (no clicks, no search, no import), then terminated. This
# measures startup plus idle cost, which is comparable across
# stacks; it does not measure interaction cost, for which a
# scripted workload (a profiling dataset) would be needed.
#
# No sudo is used: /proc/<pid>/smaps is readable for your own
# processes, and Xvfb runs as your own user. If the app fails
# to start (for example, winit loads libxkbcommon-x11 at
# runtime on X11, and that library is missing), the script
# reports the failure and writes no row, rather than a row
# of zeroes.
set -euo pipefail

# Run from this script's directory, so it works from anywhere.
cd "$(dirname "$0")"

STACK="rust-egui"
OUTPUT="performance_metrics.csv"
DURATION=10
INTERVAL=1
JOBS="$(nproc)"

usage() {
    echo "Usage: $0 [--output FILE] [--duration SECONDS] [--interval SECONDS] [--jobs N]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --output)
            OUTPUT="$2"; shift 2
            ;;
        --duration)
            DURATION="$2"; shift 2
            ;;
        --interval)
            INTERVAL="$2"; shift 2
            ;;
        --jobs)
            JOBS="$2"; shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            echo "Unexpected argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$JOBS" in
    ""|*[!0-9]*|0)
        echo "Jobs must be a positive number: $JOBS" >&2
        exit 1
        ;;
esac

export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo not found (looked in \$HOME/.cargo/bin too)." >&2
    exit 1
fi
if ! command -v Xvfb >/dev/null 2>&1; then
    echo "Xvfb not found: runtime measurements need an X server." >&2
    exit 1
fi

# Measure one build, printing only its wall time in seconds
# (to the millisecond) on stdout. Build output goes to stderr
# so it does not pollute the captured time.
#   $1 = debug | release, $2 = clean | cached
measure_build() {
    local mode="$1" type="$2"
    local start_ns end_ns ms sec rem
    if [ "$type" = "clean" ]; then
        cargo clean >&2
    fi
    start_ns=$(date +%s%N)
    if [ "$mode" = "debug" ]; then
        cargo build -j "$JOBS" >&2
    else
        cargo build --release -j "$JOBS" >&2
    fi
    end_ns=$(date +%s%N)
    ms=$(( (end_ns - start_ns) / 1000000 ))
    sec=$(( ms / 1000 ))
    rem=$(( ms % 1000 ))
    printf '%d.%03d' "$sec" "$rem"
}

# Total CPU time (user + system, all threads) for a PID, in
# clock ticks. Fields after the parenthesised comm in
# /proc/<pid>/stat are shifted by two, so utime/stime are
# fields 12 and 13 of what remains.
cpu_ticks() {
    local pid="$1"
    awk '{ sub(/^.*\) /, ""); print $12 + $13 }' "/proc/$pid/stat" 2>/dev/null || echo 0
}

# Total PSS in kB for a PID, summed over smaps, as in
# profile_memory_linux.sh.
pss_kb() {
    local pid="$1"
    if [ ! -r "/proc/$pid/smaps" ]; then
        echo 0
        return
    fi
    awk '/^Pss:/ {sum += $2} END {print sum + 0}' "/proc/$pid/smaps"
}

# Run one binary under Xvfb for $DURATION seconds, sampling
# memory and CPU every $INTERVAL seconds, and print one
# comma-separated line on stdout:
#   memory_peak_kb,memory_average_kb,cpu_peak_percent,cpu_average_percent
# Returns non-zero (and prints nothing on stdout) if no
# sample could be taken, e.g. the app exited at once.
#   $1 = absolute path to the binary
measure_runtime() {
    local binary="$1"
    if [ ! -x "$binary" ]; then
        echo "Runtime binary missing or not executable: $binary" >&2
        return 1
    fi
    local workdir disp xvfb_pid app_pid
    local samples=0 pss_sum=0 pss_peak=0
    local cpu_sum="0" cpu_peak="0"
    local prev_ticks prev_ns now_ns ticks pss wall cpu_pct
    local elapsed=0

    workdir="$(mktemp -d)"
    # Pick a free X display, 99 downwards.
    disp=""
    for candidate in 99 98 97 96 95 94 93 92 91 90; do
        if [ ! -e "/tmp/.X${candidate}-lock" ] && [ ! -e "/tmp/.X11-unix/X${candidate}" ]; then
            disp="$candidate"
            break
        fi
    done
    if [ -z "$disp" ]; then
        echo "No free X display in 90..99." >&2
        rm -rf "$workdir"
        return 1
    fi

    Xvfb ":$disp" -screen 0 1280x720x24 >"$workdir/xvfb.log" 2>&1 &
    xvfb_pid=$!
    # Wait for the X server to be ready, up to 5 seconds.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if [ -e "/tmp/.X${disp}-lock" ]; then
            break
        fi
        if ! kill -0 "$xvfb_pid" 2>/dev/null; then
            echo "Xvfb failed to start (log kept in $workdir/xvfb.log)." >&2
            return 1
        fi
        sleep 0.5
    done

    # Launch from the temp directory, so the app's recipes.db
    # and images/ land there, not in this stack folder.
    # exec is essential: without it, $! is the subshell's PID
    # (a bash process, ~700 kB PSS, ~0% CPU), not the app's,
    # so every memory/CPU sample would measure the shell.
    (cd "$workdir" && DISPLAY=":$disp" exec "$binary" >"$workdir/app.log" 2>&1) &
    app_pid=$!
    local run_start_ns
    run_start_ns=$(date +%s%N)
    # If the app exits at once, surface its log instead of
    # silently recording zeroes.
    sleep 1
    if ! kill -0 "$app_pid" 2>/dev/null; then
        echo "App exited within 1s; log kept in $workdir/app.log:" >&2
        cat "$workdir/app.log" >&2 || true
        kill "$xvfb_pid" 2>/dev/null || true
        return 1
    fi

    prev_ticks=$(cpu_ticks "$app_pid")
    prev_ns=$(date +%s%N)
    while [ "$elapsed" -lt "$DURATION" ]; do
        sleep "$INTERVAL"
        if ! kill -0 "$app_pid" 2>/dev/null; then
            break
        fi
        pss=$(pss_kb "$app_pid")
        ticks=$(cpu_ticks "$app_pid")
        now_ns=$(date +%s%N)
        wall=$(awk -v n="$now_ns" -v p="$prev_ns" 'BEGIN {printf "%.3f", (n - p) / 1000000000}')
        cpu_pct=$(awk -v t="$ticks" -v pt="$prev_ticks" -v w="$wall" -v hz="$(getconf CLK_TCK)" 'BEGIN {if (w > 0) printf "%.2f", (t - pt) / hz / w * 100; else print "0.00"}')
        samples=$(( samples + 1 ))
        pss_sum=$(( pss_sum + pss ))
        if [ "$pss" -gt "$pss_peak" ]; then
            pss_peak="$pss"
        fi
        cpu_sum=$(awk -v a="$cpu_sum" -v b="$cpu_pct" 'BEGIN {printf "%.2f", a + b}')
        cpu_peak=$(awk -v a="$cpu_peak" -v b="$cpu_pct" 'BEGIN {if (b + 0 > a + 0) print b; else print a}')
        prev_ticks="$ticks"
        prev_ns="$now_ns"
        # Elapsed is wall time since launch, so fractional
        # intervals still end the run at $DURATION seconds.
        elapsed=$(awk -v n="$now_ns" -v s="$run_start_ns" 'BEGIN {printf "%d", (n - s) / 1000000000}')
    done

    # Terminate the app, then the X server.
    if kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$app_pid" 2>/dev/null || break
            sleep 0.5
        done
        kill -9 "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    kill "$xvfb_pid" 2>/dev/null || true
    wait "$xvfb_pid" 2>/dev/null || true

    if [ "$samples" -eq 0 ]; then
        echo "No runtime samples taken (app exited during the run)." >&2
        rm -rf "$workdir"
        return 1
    fi
    rm -rf "$workdir"
    local pss_avg cpu_avg
    pss_avg=$(( pss_sum / samples ))
    cpu_avg=$(awk -v s="$cpu_sum" -v n="$samples" 'BEGIN {printf "%.2f", s / n}')
    printf '%s,%s,%s,%s' "$pss_peak" "$pss_avg" "$cpu_peak" "$cpu_avg"
}

timestamp=$(date '+%Y-%m-%d %H:%M:%S')
# Order matters: `cargo clean` removes the whole target/
# directory, not just one profile, so each mode's runtime
# run must happen before the next mode's clean build deletes
# that mode's binary.
echo "=== $STACK: debug clean build ===" >&2
clean_debug=$(measure_build debug clean)
echo "=== $STACK: debug cached build ===" >&2
cached_debug=$(measure_build debug cached)
size_debug=$(stat -c%s target/debug/rust-egui)
echo "=== $STACK: debug runtime ($DURATION s idle) ===" >&2
runtime_debug=$(measure_runtime "$PWD/target/debug/rust-egui")
IFS=',' read -r mem_peak_debug mem_avg_debug cpu_peak_debug cpu_avg_debug <<< "$runtime_debug"
echo "=== $STACK: release clean build ===" >&2
clean_release=$(measure_build release clean)
echo "=== $STACK: release cached build ===" >&2
cached_release=$(measure_build release cached)
size_release=$(stat -c%s target/release/rust-egui)
echo "=== $STACK: release runtime ($DURATION s idle) ===" >&2
runtime_release=$(measure_runtime "$PWD/target/release/rust-egui")
IFS=',' read -r mem_peak_release mem_avg_release cpu_peak_release cpu_avg_release <<< "$runtime_release"

if [ ! -s "$OUTPUT" ]; then
    echo "timestamp,stack,compile_time_clean_debug_seconds,compile_time_cached_debug_seconds,compile_time_clean_release_seconds,compile_time_cached_release_seconds,binary_size_debug_bytes,binary_size_release_bytes,memory_peak_debug_kb,memory_average_debug_kb,memory_peak_release_kb,memory_average_release_kb,cpu_peak_debug_percent,cpu_average_debug_percent,cpu_peak_release_percent,cpu_average_release_percent" > "$OUTPUT"
fi
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$timestamp" "$STACK" \
    "$clean_debug" "$cached_debug" "$clean_release" "$cached_release" \
    "$size_debug" "$size_release" \
    "$mem_peak_debug" "$mem_avg_debug" "$mem_peak_release" "$mem_avg_release" \
    "$cpu_peak_debug" "$cpu_avg_debug" "$cpu_peak_release" "$cpu_avg_release" >> "$OUTPUT"

echo "Results appended to $OUTPUT"
