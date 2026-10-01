#!/usr/bin/env bash
# Performance baseline harness for the Decision library.
#
# Runs bench/decision_bench.aql — a hot loop that builds a priority-policy
# decision table, a multi-level decision tree, and a compound predicate ONCE,
# then evaluates them across many synthetic inputs.
#
# Single execution path (boru main since 2026-09-19): every program compiles to
# bytecode and runs on the VM, or fails with `[boru/compile_failed]`. There is
# no interpreter fallback and the old `-no-compile` / `--force-compile` flags
# are RETIRED (passing them is a usage error), so the interpreter-vs-compiled
# columns this harness used to report no longer exist. What it measures now:
#
#   * correctness — the printed checksum must equal the value computed
#     independently here (the count of i in [0,ITERS) with i%90>=18 and
#     i%100>=50), so a wrong answer fails loudly;
#   * best-of-N wall time at ITERS iterations, and at 1 iteration (the fixed
#     parse + check + compile overhead), giving the per-iteration cost.
#
# Resolving the boru build: $BORU (or the legacy $BENCH_AQL / $BYTECODE_AQL),
# else the on-PATH `boru`.
#
#   BORU=/path/to/boru bash bench/bench.sh
#   ITERS=3000 RUNS=5  bash bench/bench.sh
set -uo pipefail
cd "$(dirname "$0")/.."   # repo root

BORU_BIN="${BORU:-${BENCH_AQL:-${BYTECODE_AQL:-boru}}}"
ITERS="${ITERS:-3000}"
RUNS="${RUNS:-3}"
SRC="bench/decision_bench.aql"

command -v "$BORU_BIN" >/dev/null 2>&1 || { echo "no boru binary ($BORU_BIN); set BORU"; exit 2; }

# Materialise the benchmark at the requested iteration count. The copies live
# NEXT TO the source: a relative import resolves against the importing file's
# own directory, so `import "../decision.aql"` must keep pointing at the repo.
work="bench/.bench-work-$$.aql"; over="bench/.bench-over-$$.aql"
trap 'rm -f "$work" "$over"' EXIT
sed "s/^for [0-9]* \[/for ${ITERS} [/" "$SRC" > "$work"
sed "s/^for [0-9]* \[/for 1 [/" "$SRC" > "$over"

secs() { python3 -c 'import sys,time,subprocess;a=sys.argv[1:];t=time.perf_counter();subprocess.run(a,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);print(f"{time.perf_counter()-t:.4f}")' "$@"; }
best() { # best-of-$RUNS wall seconds for: <file>
  local b=1e9 i d
  for ((i=0;i<RUNS;i++)); do d="$(secs "$BORU_BIN" "$1")"; awk "BEGIN{exit !($d<$b)}" && b="$d"; done
  echo "$b"
}

want="$(python3 -c "import sys;n=int(sys.argv[1]);print(sum(1 for i in range(n) if i%90>=18 and i%100>=50))" "$ITERS")"
got="$("$BORU_BIN" "$work" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] || [ "$got" != "$want" ]; then
  echo "FAILED: rc=$rc checksum=[$got] want=[$want]"; exit 1
fi
echo "boru:     $("$BORU_BIN" -version 2>/dev/null || echo "$BORU_BIN")"
echo "workload: $SRC   iters=$ITERS   runs=$RUNS   checksum=$got (expected $want)"
echo

o="$(best "$over")"
t="$(best "$work")"

awk -v o="$o" -v t="$t" -v n="$ITERS" 'BEGIN{
  printf "%-24s %.4f\n", "total wall (s)", t;
  printf "%-24s %.4f\n", "fixed overhead (s)", o;
  printf "%-24s %.1f\n", "per-iter exec (us)", (t-o)/n*1e6;
}'
