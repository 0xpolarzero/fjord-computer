#!/bin/bash
# The motions' frames and latencies, without a person or a pointer (docs/design/fjord/glass-plan.md §7, §8.2). Records the
# release build with `xcrun xctrace` (the Hitches and os_signpost instruments by default) while it plays a motion script on demo data
# (`--demo <scenario> --motion-script <steps> --quit-after`: the app opens and closes its window as the shortcut does, folds
# the sidebar, peeks the bar's inbox and drags the bar to the opposite edge, one step every 1.5 s, and quits). Then exports
# the trace's table of contents, its hitches and its signpost intervals, and prints:
#
#   - the hitches during the app's motions (inside one of its intervals), and how many within each; the instrument also
#     reports the app late some 12 times a second at rest, drawing nothing, so the rest are noise;
#   - each signpost interval of the app (subsystem com.amontlabs.fjord: the morph's and the latency ones, "Peek", "Fold",
#     "Drag", "Bar away", "Bar capture"): how many, p50, p95 and the longest, in ms. A "Bar away" ended "kept" (the bar was
#     away already) is left out.
#
# The summary is written as JSON beside the trace. `--baseline FILE` stores it when FILE does not exist, and compares with
# it when it does: more hitches than the baseline's, or an interval's p95 more than SLACK_MS (default 1) above the
# baseline's, fails. The budgets themselves (§7) are read from the numbers: this only says what got worse.
#
# Other templates show what the hitches don't: `--template time` (Time Profiler, the main thread during the fold), `swiftui`
# (the SwiftUI template's layout lane), `metal` (Metal System Trace). The os_signpost instrument is added to every one.
# Nothing here needs sudo. The app takes the screen for the length of the script (some 1.5 s per step), and focus when its
# window opens: no typing meanwhile.
#
#   scripts/motion-trace.sh                                   build (release), record the default script, print
#   scripts/motion-trace.sh --steps "open,close x20" --scenario busy
#   scripts/motion-trace.sh --template time --steps "open,fold,fold,close x20"
#   scripts/motion-trace.sh --baseline docs/design/fjord/baselines/motion.json     store, then compare
#   scripts/motion-trace.sh --keep /tmp/motion                keep the trace and its exports there
#   SKIP_BUILD=1 SLACK_MS=2 scripts/motion-trace.sh           use the release build as it is; a looser p95 comparison
set -u
cd "$(dirname "$0")/.." || exit 2

template="Hitches"
scenario=busy
# Five rounds: enough for p95s, short enough that a trace stays small.
steps="open,fold,fold,close,peek,drag x5"
baseline=
keep=
slack=${SLACK_MS:-1}
bin=.build/release/Fjord

while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || { echo "motion-trace: $1 needs a value"; exit 2; }
    case "$1" in
        --template)
            case "$2" in
                hitches) template="Hitches" ;;
                time) template="Time Profiler" ;;
                swiftui) template="SwiftUI" ;;
                metal) template="Metal System Trace" ;;
                *) template=$2 ;;
            esac ;;
        --scenario) scenario=$2 ;;
        --steps) steps=$2 ;;
        --baseline) baseline=$2 ;;
        --keep) keep=$2 ;;
        *) echo "motion-trace: unknown argument '$1' (--template, --scenario, --steps, --baseline, --keep)"; exit 2 ;;
    esac
    shift 2
done

# The app refuses a script it can't read too; this says so before a build and a recording.
step='(open|close|fold|peek|drag)'
pattern="^$step(,$step)*( x[1-9][0-9]*)?\$"
[[ "$steps" =~ $pattern ]] || { echo "motion-trace: --steps is like 'open,close,fold,peek,drag x20' ('$steps' is not)"; exit 2; }
[[ "$slack" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "motion-trace: SLACK_MS is a number ('$slack' is not)"; exit 2; }
[ -z "$baseline" ] || [ ! -e "$baseline" ] || [ -f "$baseline" ] || { echo "motion-trace: $baseline is not a file"; exit 2; }
command -v python3 >/dev/null || { echo "motion-trace: python3 is needed for the export"; exit 2; }

if [ "${SKIP_BUILD:-0}" != "1" ]; then
    swift build -c release >/dev/null || { echo "motion-trace: release build failed"; exit 2; }
fi
[ -x "$bin" ] || { echo "motion-trace: $bin not found"; exit 2; }

# Instruments writes its raw data to the user's temp folder (instruments*.ktrace, xrgpu_aps_*: some 2 GB a second with
# Animation Hitches, which records the whole system and its GPU) and leaves it there when a recording is stopped or hangs.
# So: no start under MIN_FREE_GB free, and on any exit the files this run made there are deleted.
scratch=$(getconf DARWIN_USER_TEMP_DIR)
free_gb=$(df -g "$scratch" | awk 'NR==2 {print $4}')
if [ "${free_gb:-0}" -lt "${MIN_FREE_GB:-80}" ]; then
    echo "motion-trace: ${free_gb} GB free, under ${MIN_FREE_GB:-80}: Instruments' scratch could fill the disk"; exit 2
fi
mark=$(mktemp)
cleanup() {
    find "$scratch" -maxdepth 1 -type f \( -name 'instruments*.ktrace' -o -name 'xrgpu_aps_*' \) -newer "$mark" -delete
    rm -f "$mark"
    [ -n "$keep" ] || rm -rf "$dir"
}
trap cleanup EXIT
trap 'pkill -INT -f "xctrace record.*$trace"; exit 130' INT TERM

if [ -n "$keep" ]; then
    mkdir -p "$keep" || exit 2
    dir=$keep
else
    dir=$(mktemp -d)
fi
trace=$dir/motion.trace
rm -rf "$trace"

# How long the script takes, and a time limit past it, so a script that never ends doesn't record forever.
count=1
[[ "$steps" =~ x([0-9]+)$ ]] && count=${BASH_REMATCH[1]}
names=${steps%% x*}
played=$(( $(tr ',' '\n' <<<"$names" | wc -l) * count ))
# Each step takes 1.5 s; a peek holds 0.7 s more (MotionScript.peekHold).
peeks=$(( $(tr ',' '\n' <<<"$names" | grep -c '^peek$') * count ))
seconds=$(( (played * 15 + peeks * 7) / 10 ))
limit=$(( seconds + 30 ))
echo "motion-trace: $template, --demo $scenario, $played steps (about $(( seconds + 5 )) s)"

# The hitches alone are two instruments, not the Animation Hitches template: the template traces the whole system and
# its GPU (hundreds of MB a second); these two take some 2 MB a second.
if [ "$template" = Hitches ]; then what=(--instrument Hitches); else what=(--template "$template"); fi
xcrun xctrace record "${what[@]}" --instrument os_signpost --no-prompt --quiet \
    --output "$trace" --time-limit "${limit}s" --target-stdout "$dir/app.out" \
    --launch -- "$bin" --demo "$scenario" --motion-script "$steps" --quit-after
recorded=$?
[ -d "$trace" ] || { echo "motion-trace: no trace was recorded (xctrace exited $recorded)"; exit 2; }
if ! grep -q '^motion: done' "$dir/app.out" 2>/dev/null; then
    echo "motion-trace: the script did not finish (the time limit, or the app ended early); the numbers are partial"
fi
notes=$(grep -c '^motion: .*(' "$dir/app.out" 2>/dev/null)
[ "${notes:-0}" = 0 ] || echo "motion-trace: $notes steps did nothing (the app's lines: $dir/app.out, kept with --keep)"

xcrun xctrace export --input "$trace" --toc --output "$dir/toc.xml" || { echo "motion-trace: the table of contents can't be exported"; exit 2; }

# The tables to read: the hitches (Animation Hitches' "hitches") and the signpost intervals. A "|" between them, not a tab:
# `read` would fold an empty first field into the separator.
schemas=$(python3 -I - "$dir/toc.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
names = [t.get("schema") for t in ET.parse(sys.argv[1]).getroot().iter("table") if t.get("schema")]
hitches = "hitches" if "hitches" in names else ""
signposts = "os-signpost-interval" if "os-signpost-interval" in names else ""
print(hitches, signposts, sep="|")
PY
) || { echo "motion-trace: the table of contents can't be read"; exit 2; }
IFS='|' read -r hitch_schema signpost_schema <<<"$schemas"
[ -n "$hitch_schema" ] || echo "motion-trace: no hitches in this trace (the $template template has none)"
[ -n "$signpost_schema" ] || echo "motion-trace: no signpost intervals in this trace"
for schema in $hitch_schema $signpost_schema; do
    xcrun xctrace export --input "$trace" --output "$dir/$schema.xml" \
        --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$schema\"]" \
        || { echo "motion-trace: the $schema table can't be exported"; exit 2; }
done

python3 -I - "$dir" "$hitch_schema" "$signpost_schema" "$template" "$scenario" "$steps" "$baseline" "$slack" <<'PY'
import json, math, os, sys, time, xml.etree.ElementTree as ET

folder, hitch_schema, signpost_schema, template, scenario, steps, baseline, slack = sys.argv[1:9]
slack = float(slack)
SUBSYSTEM, APP = "com.amontlabs.fjord", "Fjord"

def rows(schema):
    """The table's rows as {column: (raw text, fmt)}; a cell given as ref="n" is the one with id="n"."""
    if not schema:
        return []
    root = ET.parse(os.path.join(folder, schema + ".xml")).getroot()
    ids = {e.get("id"): e for e in root.iter() if e.get("id")}
    out = []
    for node in root.iter("node"):
        cols = [c.findtext("mnemonic") for c in node.iter("col")]
        for row in node.iter("row"):
            cells = {}
            for col, cell in zip(cols, list(row)):
                cell = ids.get(cell.get("ref"), cell)
                cells[col] = ((cell.text or "").strip(), cell.get("fmt", ""))
            out.append(cells)
    return out

def number(cells, col):
    try:
        return float(cells[col][0])
    except (KeyError, ValueError):
        return None

intervals = {}
for r in rows(signpost_schema):
    if r.get("subsystem", ("", ""))[1] != SUBSYSTEM and r.get("subsystem", ("", ""))[0] != SUBSYSTEM:
        continue
    name = r.get("name", ("", ""))[1] or r.get("name", ("", ""))[0]
    if name == "Bar away" and "kept" in (r.get("end-message", ("", ""))[1], r.get("end-message", ("", ""))[0]):
        continue
    start, duration = number(r, "start"), number(r, "duration")
    if start is not None and duration is not None:
        intervals.setdefault(name, []).append((start, duration))

hitches = []
for r in rows(hitch_schema):
    start, duration = number(r, "start"), number(r, "duration")
    if start is None or not duration:
        continue
    process = r.get("process", ("", ""))[1]
    hitches.append((start, duration, APP in process))
app_hitches = [h for h in hitches if h[2]]

def percentile(xs, p):
    xs = sorted(xs)
    return xs[max(0, math.ceil(p / 100 * len(xs)) - 1)]

summary = {"template": template, "scenario": scenario, "steps": steps, "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
           "hitches": None, "intervals": {}}
if hitch_schema:
    within = {name: sum(1 for h in app_hitches if any(s <= h[0] < s + d for s, d in spans))
              for name, spans in intervals.items()}
    # At rest the instrument still reports the app late some 12 times a second while it draws nothing (no CPU, window
    # closed): only a hitch during one of its motions counts.
    moving = sum(1 for h in app_hitches if any(s <= h[0] < s + d for spans in intervals.values() for s, d in spans))
    summary["hitches"] = {"all": len(hitches), "app": len(app_hitches), "moving": moving, "within": within}
for name, spans in sorted(intervals.items()):
    ms = [d / 1e6 for _, d in spans]
    summary["intervals"][name] = {"n": len(ms), "p50_ms": round(percentile(ms, 50), 3),
                                  "p95_ms": round(percentile(ms, 95), 3), "max_ms": round(max(ms), 3)}

h = summary["hitches"]
if h is not None:
    print(f"hitches: {h['moving']} during the app's motions ({h['app']} attributed to it in all, most at rest: noise)")
    for name, n in sorted(h["within"].items()):
        if n:
            print(f"  within {name}: {n}")
if not summary["intervals"]:
    print("intervals: none of the app's")
for name, s in summary["intervals"].items():
    print(f"{name:22} n={s['n']:<4} p50 {s['p50_ms']:8.2f} ms  p95 {s['p95_ms']:8.2f} ms  max {s['max_ms']:8.2f} ms")

with open(os.path.join(folder, "motion.json"), "w") as f:
    json.dump(summary, f, indent=2)
    f.write("\n")

failed = False
if baseline:
    if not os.path.exists(baseline):
        os.makedirs(os.path.dirname(baseline) or ".", exist_ok=True)
        with open(baseline, "w") as f:
            json.dump(summary, f, indent=2)
            f.write("\n")
        print(f"baseline: stored in {baseline}")
    else:
        try:
            old = json.load(open(baseline))
            old_intervals = old["intervals"]
        except (OSError, ValueError, KeyError, TypeError) as e:
            print(f"baseline: FAIL: {baseline} can't be read ({e})")
            sys.exit(1)
        print(f"baseline: against {baseline} ({old.get('date', 'undated')}, {old.get('template')}, {old.get('steps')})")
        if (old.get("template"), old.get("scenario"), old.get("steps")) != (template, scenario, steps):
            print("  (recorded otherwise: the template, the scenario or the steps differ)")
        if h is not None and old.get("hitches"):
            worse = h["moving"] > old["hitches"]["moving"]
            failed |= worse
            print(f"  hitches {h['moving']} (was {old['hitches']['moving']}){'  FAIL' if worse else ''}")
        for name, s in summary["intervals"].items():
            was = old_intervals.get(name)
            if not was:
                print(f"  {name}: not in the baseline")
                continue
            worse = s["p95_ms"] > was["p95_ms"] + slack
            failed |= worse
            print(f"  {name:20} p95 {s['p95_ms']:.2f} ms (was {was['p95_ms']:.2f}, {s['p95_ms'] - was['p95_ms']:+.2f})"
                  f"{'  FAIL' if worse else ''}")

sys.exit(1 if failed else 0)
PY
verdict=$?
[ -z "$keep" ] || echo "motion-trace: the trace, its exports and motion.json are in $keep"
exit $verdict
