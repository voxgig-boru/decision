#!/usr/bin/env bash
# Multi-surface test gate — tracks the LATEST boru from `main`.
#
# boru is on an iterative-improvement track, so this gate always targets the
# newest `boru` and reports current status rather than pinning a "best" build.
#
# ONE EXECUTION PATH. Since boru main 2026-09-19 a program compiles to bytecode
# and runs on the VM, or it fails with `[boru/compile_failed] … this is a
# compiler defect`. There is no interpreter fallback, and the flags
# `--compile` / `--force-compile` / `--no-compile` (and the BORU_COMPILE /
# BORU_FORCE_COMPILE / BORU_NO_COMPILE env vars) are RETIRED — passing them is
# a usage error. So the old INTERPRETER / BYTECODE columns and the
# "compiled output == interpreter output" divergence check no longer exist:
# "the suite runs" now MEANS "the suite fully compiles". Two surfaces remain:
#
#   * RUN    — `boru suite.aql`        compile + run on the VM (which also runs
#                                       the static pre-flight check first; a
#                                       check error blocks the run)
#   * CHECK  — `boru check suite.aql`  the static checker, reported on its own
#
# Every invariant is HARD (a violation fails the gate):
#   1. every suite RUNs: exit 0, no `compile_failed`, and — for the
#      assertion-bearing suites — `all green` printed (the smoke suite carries
#      no assertions; for it, a clean exit is the pass condition);
#   2. `boru check` reports 0 errors on every suite AND on every library
#      module (decision.aql).
#
# A `compile_failed` is reported as such (it is a boru compiler defect, not a
# test failure), but it still fails the gate: on the single path a suite that
# does not compile does not run.
#
# Resolving the boru build (latest main by default):
#   1. $BORU (or the legacy $BYTECODE_AQL), if set and runnable;
#   2. else build $BORU_REF (legacy $BYTECODE_BORU_REF; default: current `main`
#      HEAD), cached by sha in ~/.local/bin. The proxy git relay is scoped, so
#      the source is fetched as an HTTPS tarball from codeload and built from
#      its cmd/go module (`go build -o … ./boru`). Requires `go` (+ network on
#      a new sha);
#   3. else (offline) the newest cached build, or the on-PATH `boru`.
#
# Run from anywhere:
#   bash test/diverge.sh
#   BORU=/path/to/boru bash test/diverge.sh     # use a specific binary
#   BORU_REF=<sha>     bash test/diverge.sh     # build a specific commit
set -uo pipefail

cd "$(dirname "$0")/.."   # repo root (suite paths below are repo-relative;
                          # their `import "../decision.aql"` resolves against
                          # each suite file's own directory)

BORU_REF="${BORU_REF:-${BYTECODE_BORU_REF:-}}"   # empty => resolve latest main HEAD
BORU_OVERRIDE="${BORU:-${BYTECODE_AQL:-}}"
API_MAIN="https://api.github.com/repos/boru-lang/boru/commits/main"
TARBALL="https://codeload.github.com/boru-lang/boru/tar.gz"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n'  "$*"; }

runnable() {
  [ -n "${1:-}" ] && command -v "$1" >/dev/null 2>&1 && "$1" -e '1 2 add' >/dev/null 2>&1
}

latest_main_sha() { curl -fsS "$API_MAIN" 2>/dev/null | grep -m1 '"sha"' | sed -E 's/.*"sha": *"([0-9a-f]+)".*/\1/'; }

# Build boru at $1 (a full sha) into a sha-named cache binary; echo its path.
build_ref() {
  local ref="$1" bin="$HOME/.local/bin/boru-main-${1:0:12}"
  if runnable "$bin"; then echo "$bin"; return 0; fi
  command -v go >/dev/null 2>&1 || { red "no \`go\` toolchain; cannot build boru @ ${ref:0:12} (see docs/how-to.md)" >&2; return 1; }
  red "building boru @ ${ref:0:12} (one-time; cached)…" >&2
  mkdir -p "$HOME/.local/bin"
  local d; d="$(mktemp -d)"
  if curl -fsSL "$TARBALL/$ref" | tar -xz -C "$d" --strip-components=1 \
     && ( cd "$d/cmd/go" && GOWORK=off GOFLAGS=-mod=mod go build \
            -ldflags "-X github.com/boru-lang/boru/cmd/go.Version=$ref" -o "$bin" ./boru ) >&2; then
    rm -rf "$d"; echo "$bin"; return 0
  fi
  rm -rf "$d"; red "build failed (see docs/how-to.md)" >&2; return 1
}

newest_cached_boru() {
  local b; for b in $(ls -t "$HOME/.local/bin/boru-main-"* 2>/dev/null); do
    runnable "$b" && { echo "$b"; return 0; }
  done; return 1
}

resolve_boru() {
  if [ -n "$BORU_OVERRIDE" ]; then
    runnable "$BORU_OVERRIDE" && { echo "$BORU_OVERRIDE"; return 0; }
    red "BORU=$BORU_OVERRIDE is not a runnable boru" >&2; return 1
  fi
  local ref="$BORU_REF"
  [ -z "$ref" ] && ref="$(latest_main_sha)"
  # A symbolic BORU_REF (main, a tag, feature/x) is mutable and may contain '/':
  # resolve it to the commit it names, so build_ref's cache key is immutable.
  case "$ref" in
    *[!0-9a-f]*)
      local sha
      sha="$(git ls-remote https://github.com/boru-lang/boru.git "$ref" 2>/dev/null | awk -v r="$ref" '
        $2==r || $2=="refs/heads/"r {h=$1} $2=="refs/tags/"r {t=$1} $2=="refs/tags/"r"^{}" {p=$1}
        END {print (h!="" ? h : (p!="" ? p : t))}')"
      [ -n "$sha" ] || { red "could not resolve BORU_REF=$ref to a boru-lang/boru commit (network?); pass a commit SHA or set BORU=/path/to/boru" >&2; return 1; }
      ref="$sha" ;;
  esac
  if [ -n "$ref" ]; then build_ref "$ref" && return 0; fi
  # Offline fallback (couldn't reach main to resolve/build latest): prefer the
  # NEWEST cached build — the best proxy for "latest" — over a possibly stale
  # on-PATH `boru`. Warn, because this may not be the true HEAD.
  local b
  if b="$(newest_cached_boru)"; then
    red "note: could not reach boru main; using newest cached build ($(basename "$b")) — may lag HEAD" >&2
    echo "$b"; return 0
  fi
  runnable boru && { red "note: could not reach boru main; using on-PATH boru — may lag HEAD" >&2; command -v boru; return 0; }
  return 1
}

BORU_BIN="$(resolve_boru)" || { red "could not resolve a runnable boru (no network and no cached build)"; exit 2; }
green "boru: $("$BORU_BIN" -version 2>/dev/null || echo "$BORU_BIN")"
# A build that still ACCEPTS a retired flag predates the single execution path
# (it can fall back to the interpreter); the gate's meaning assumes it cannot.
if "$BORU_BIN" --force-compile -e '1' >/dev/null 2>&1; then
  red "warning: this boru still accepts the retired --force-compile flag — it predates the single execution path (boru main 2026-09-19); RUN may be interpreted, not compiled" >&2
fi
echo

# Library modules: `boru check` must report 0 errors on each.
MODULES=(
  decision.aql
)

# name|assertion-bearing (1 = must print "all green")
SUITES=(
  "test/decision_unit_test.aql|1"
  "test/decision_unit_spec.aql|1"
  "test/decision_prop_test.aql|1"
  "test/decision_prop_spec.aql|1"
  "test/decision_smoke_test.aql|0"
)

check_errors() { # echo the checker's error count for $1 ("?" if unparsed)
  local out="$1" n
  n="$(printf '%s' "$out" | grep -oE '[0-9]+ error\(s\)' | tail -1)"; n="${n% error(s)}"
  echo "${n:-?}"
}

fail=0
ran=0          # suites that ran clean (== fully compiled + passed)
checkclean=0   # suites + modules that checked with 0 errors
for mod in "${MODULES[@]}"; do
  chk_out="$("$BORU_BIN" check "$mod" 2>&1)"; chk_rc=$?; cerr="$(check_errors "$chk_out")"
  line="$(printf '%-28s %s' "$mod" "check ${cerr} err (module)")"
  if [ "$chk_rc" -eq 0 ] && [ "$cerr" = "0" ]; then checkclean=$((checkclean+1)); green "$line"
  else fail=1; red "$line"; printf '%s\n' "$chk_out" | grep -iE "error" | sed 's/^/    check | /'; fi
done

for entry in "${SUITES[@]}"; do
  suite="${entry%%|*}"; asserts="${entry##*|}"; name="${suite#test/}"; notes=(); bad=0

  run_out="$("$BORU_BIN" "$suite" 2>&1)"; run_rc=$?
  if printf '%s' "$run_out" | grep -q 'boru/compile_failed'; then
    notes+=("run COMPILE_FAILED (compiler defect)"); bad=1
  elif [ "$run_rc" -ne 0 ]; then
    notes+=("run FAIL(rc=$run_rc)"); bad=1
  elif [ "$asserts" = "1" ] && ! printf '%s\n' "$run_out" | grep -qx 'all green'; then
    notes+=("run FAIL(no 'all green')"); bad=1
  else
    notes+=("run ok (compiled)"); ran=$((ran+1))
  fi

  chk_out="$("$BORU_BIN" check "$suite" 2>&1)"; chk_rc=$?; cerr="$(check_errors "$chk_out")"
  if [ "$chk_rc" -eq 0 ] && [ "$cerr" = "0" ]; then notes+=("check ok (0 err)"); checkclean=$((checkclean+1))
  else notes+=("check FAIL(${cerr} err)"); bad=1; fi

  joined=""; for n in "${notes[@]}"; do joined+="${joined:+  |  }$n"; done
  line="$(printf '%-28s %s' "$name" "$joined")"
  if [ "$bad" -ne 0 ]; then
    fail=1; red "$line"
    [ "${notes[0]#run ok}" = "${notes[0]}" ] && printf '%s\n' "$run_out" | tail -15 | sed 's/^/    run   | /'
    [ "$chk_rc" -ne 0 ] && printf '%s\n' "$chk_out" | grep -iE "error" | sed 's/^/    check | /'
  else
    green "$line"
  fi
done

total=$(( ${#SUITES[@]} + ${#MODULES[@]} ))
echo "---"
dim "status: ${ran}/${#SUITES[@]} suites run (fully compiled) and pass; ${checkclean}/${total} files check-clean (${#SUITES[@]} suites + ${#MODULES[@]} module)."
if [ "$fail" -ne 0 ]; then
  red "FAILED: a suite did not compile/run/pass, or \`boru check\` reported an error"
  exit 1
fi
green "OK: every suite compiles, runs and passes; every suite and module checks with 0 errors"
