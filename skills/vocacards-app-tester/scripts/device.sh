#!/usr/bin/env bash
# VocaCards device helper (Git Bash). Read-only except `pulldb`, which writes to the
# device's /data/local/tmp and removes what it wrote.
#
#   device.sh fg <serial> [package]            exit 1 unless <package> is in front and awake
#   device.sh preflight <serial>               packages, debuggability, foreground, Metro reach
#   device.sh pulldb <serial> [package] [dir]  binary-safe copy of vocacards.db + -wal + -shm
#
# package defaults to cards.voca.app (release). The dev variant is cards.voca.app.dev.
# ponytail: UNTESTED as of 2026-09-25 (written with a no-tests instruction in force).
# Run `preflight` once against a device before trusting `fg` in a chain.
set -u
export MSYS_NO_PATHCONV=1   # otherwise Git Bash rewrites /data/local/tmp into a Windows path
command -v adb >/dev/null || export PATH="$PATH:/c/Users/Luk/AppData/Local/Android/Sdk/platform-tools"

die() { echo "device.sh: $*" >&2; exit 1; }
sh_() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }

fg() {
  local pkg=${1:-cards.voca.app} act focus wake
  # POCO reports topResumedActivity, the Redmi mResumedActivity: accept either.
  act=$(sh_ "dumpsys activity activities | grep -E -m1 'topResumedActivity|mResumedActivity'")
  focus=$(sh_ "dumpsys window | grep -m1 mCurrentFocus")
  wake=$(sh_ "dumpsys power | grep -m1 mWakefulness=")
  echo "$act"; echo "$focus"; echo "$wake"
  # Match " <pkg>/" so cards.voca.app never matches cards.voca.app.dev.
  case "$act" in *" $pkg/"*) ;; *) die "NOT IN FRONT: $pkg (stop; screenshot; ask before tapping)";; esac
  case "$focus" in *" $pkg/"*) ;; *) die "NOT FOCUSED: $pkg (a dialog or another window has focus)";; esac
  case "$wake" in *Awake*) ;; *) die "SCREEN NOT AWAKE: taps would be swallowed";; esac
}

preflight() {
  adb devices -l
  echo "model: $(sh_ getprop ro.product.model)  android: $(sh_ getprop ro.build.version.release)"
  for p in cards.voca.app cards.voca.app.dev; do
    if sh_ "pm path $p" | grep -q package:; then
      if sh_ "run-as $p true 2>&1" | grep -q .; then d="NOT debuggable (no run-as / pulldb)"; else d="debuggable"; fi
      echo "installed: $p  $d"
    else
      echo "absent:    $p"
    fi
  done
  sh_ "dumpsys activity activities | grep -E -m1 'topResumedActivity|mResumedActivity'"
  sh_ "dumpsys window | grep -m1 mCurrentFocus"
  sh_ "dumpsys power | grep -m1 mWakefulness="
  echo "--- adb reverse:"; adb -s "$SERIAL" reverse --list
  for port in $(adb -s "$SERIAL" reverse --list | grep -oE 'tcp:[0-9]+' | cut -d: -f2 | sort -u); do
    code=$(sh_ "curl -s -m 3 -o /dev/null -w '%{http_code}' http://localhost:$port/status")
    host=$(netstat -ano 2>/dev/null | grep -E "LISTENING" | grep -E ":$port " | awk '{print $2}' | tr '\n' ' ')
    echo "metro :$port  device-side /status=$code  host binds: ${host:-none}  (want 200 and 0.0.0.0)"
  done
  echo "Reminder: a peer session may be using this device. Check ListAgents before driving it."
}

pulldb() {
  local pkg=${1:-cards.voca.app} out=${2:-/c/tmp/vc-$SERIAL} s
  sh_ "run-as $pkg true 2>&1" | grep -q . && die "$pkg is not debuggable: run-as refused (release build?)"
  mkdir -p "$out" || die "cannot create $out"
  # Never `adb exec-out cat > file` here: in Git Bash it yields a right-sized, corrupt DB.
  for s in "" -wal -shm; do
    # sh_ pipes through tr, so read output rather than exit status; plain adb shell for status.
    if sh_ "run-as $pkg ls files/SQLite/vocacards.db$s 2>&1" | grep -q 'No such file'; then echo "skip: vocacards.db$s absent"; continue; fi
    adb -s "$SERIAL" shell "run-as $pkg cat files/SQLite/vocacards.db$s > /data/local/tmp/vc.db$s" || die "copy failed: $s"
    adb -s "$SERIAL" pull "/data/local/tmp/vc.db$s" "$(cygpath -w "$out")\\vocacards.db$s" || die "pull failed: $s"
    adb -s "$SERIAL" shell "rm -f /data/local/tmp/vc.db$s"
  done
  ls -l "$out"
  echo "Query from the repo root with Node 22 + better-sqlite3, or: npx tsx scripts/probe-queue-divergence.ts"
}

cmd=${1:-}; SERIAL=${2:-}
[ -n "$cmd" ] && [ -n "$SERIAL" ] || die "usage: device.sh fg|preflight|pulldb <serial> [...]"
shift 2
case "$cmd" in
  fg) fg "$@" ;;
  preflight) preflight ;;
  pulldb) pulldb "$@" ;;
  *) die "unknown command: $cmd" ;;
esac
