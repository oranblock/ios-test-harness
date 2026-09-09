#!/usr/bin/env bash
# Shared helpers for flow scripts. Source this, don't run it:
#
#   source "$(dirname "$0")/../scripts/lib.sh"
#
# Every helper captures a screenshot, snips the log tail, and (if Telegram
# secrets are set) pushes a live photo. The point is that a flow file reads as
# the test, not as plumbing.
#
# Provided by the workflow: UDID, BUNDLE_ID, REPORT_DIR, TELEGRAM_* (optional).

set -euo pipefail

: "${UDID:?UDID not set — run this from the workflow}"
: "${BUNDLE_ID:?BUNDLE_ID not set}"
: "${REPORT_DIR:?REPORT_DIR not set}"

STEP_N=0

# --- internals ---------------------------------------------------------------

_tg_enabled() { [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; }

# Telegram captions are HTML with %0A newlines, so anything from the app's logs
# has to be escaped or a stray < silently truncates the message.
_html_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# idb drives taps, swipes and rotation. It is OPTIONAL: Homebrew now refuses the
# facebook/fb tap on some runner images, and everything that actually catches a
# crash — launch, screenshot, process liveness — is pure simctl. When idb is
# missing those helpers log and skip instead of failing the run, so a smoke test
# still reports the failures that matter.
# `command -v idb` is not enough: the CLI can be installed while no companion is
# reachable, which fails at USE time with "no udid provided and there no
# companions". Every idb call therefore passes --udid explicitly, and this probes
# a real command rather than the binary's existence.
HAVE_IDB=0
if command -v idb >/dev/null 2>&1 && idb list-targets --udid "$UDID" >/dev/null 2>&1; then
  HAVE_IDB=1
fi
[ "$HAVE_IDB" = 1 ] || echo "!! idb unavailable — tap/type/swipe/rotate will be SKIPPED (launch + crash checks still run)"

_need_idb() {
  if [ "$HAVE_IDB" = 1 ]; then return 0; fi
  echo "  ~ skipped ($1): idb unavailable"
  return 1
}

# --- helpers you use in flows ------------------------------------------------

# send_step <name> [note]  — screenshot + log tail, no interaction
send_step() {
  local name="$1" note="${2:-}"
  STEP_N=$((STEP_N + 1))
  local label
  label=$(printf '%02d_%s' "$STEP_N" "$name")
  local shot="${REPORT_DIR}/screenshots/${label}.png"
  local snip="${REPORT_DIR}/logs/${label}.txt"

  xcrun simctl io "$UDID" screenshot "$shot" >/dev/null 2>&1 || {
    echo "  ! screenshot failed at ${label}"; return 0; }
  tail -n 25 "${REPORT_DIR}/logs/app_process.log" > "$snip" 2>/dev/null || echo "(no logs)" > "$snip"

  echo "  → ${label}${note:+ — $note}"
  _tg_enabled || return 0

  local body
  body=$(tail -n 4 "$snip" | _html_escape)
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
    -F chat_id="${TELEGRAM_CHAT_ID}" \
    -F photo="@${shot}" \
    -F caption="📸 <b>${label}</b> $(date +%H:%M:%S)${note:+%0A${note}}%0A<code>${body}</code>" \
    -F parse_mode="HTML" -o /dev/null || echo "  ! telegram send failed (continuing)"
}

# tap <x> <y> <name>
tap() { _need_idb "tap $3" || return 0; echo "tap ($1,$2)"; idb ui tap --udid "$UDID" "$1" "$2"; sleep "${TAP_SETTLE:-1}"; send_step "$3"; }

# type_text <text> <name>
type_text() { _need_idb "type $2" || return 0; echo "type"; idb ui text --udid "$UDID" "$1"; sleep 1; send_step "$2"; }

# swipe <x1> <y1> <x2> <y2> <name>
swipe() { _need_idb "swipe $5" || return 0; echo "swipe"; idb ui swipe --udid "$UDID" "$1" "$2" "$3" "$4"; sleep 1; send_step "$5"; }

# press <HOME|LOCK|SIRI> <name>
# Falls back to terminate: without idb there is no HOME button, but killing and
# relaunching exercises the same cold-start path a resume crash hides in.
press() {
  if [ "$HAVE_IDB" = 1 ]; then idb ui button --udid "$UDID" "$1"; else echo "  ~ no idb: terminating instead of pressing $1"; terminate; fi
  sleep 1; send_step "$2"
}

# launch [name] — cold start
launch() {
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep "${LAUNCH_SETTLE:-5}"
  send_step "${1:-launched}"
}

terminate() { xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true; }

# assert_running <name> — the cheapest real assertion available without a test
# runner inside the app: is the process still alive after what we just did?
assert_running() {
  if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    send_step "${1:-still_running}" "process alive"
  else
    send_step "${1:-CRASHED}" "⚠️ process is GONE — likely a crash"
    echo "::error::$BUNDLE_ID is no longer running after step ${STEP_N}"
    return 1
  fi
}

# A flow that dies should still leave evidence, so capture the final frame
# whatever happens.
trap 'rc=$?; [ $rc -ne 0 ] && send_step "FAILURE_final_frame" "exit $rc" || true' EXIT
