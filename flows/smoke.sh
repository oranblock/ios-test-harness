#!/usr/bin/env bash
# Default flow. Knows NOTHING about the app, so it works on any project on day
# one: launch it, prove it stays up, background and restore it, look for a crash.
#
# That is a low bar deliberately — the two failures worth catching before you
# have written any real flow are "does not launch" and "dies on resume", and
# both are invisible to a build that merely compiles.
source "$(dirname "$0")/../scripts/lib.sh"

echo "== smoke: $BUNDLE_ID =="

launch "cold_launch"
assert_running "after_launch"

# Settle: first-frame screenshots often catch a splash rather than the app.
sleep 3
send_step "settled"

# Background/foreground is where state-restoration bugs surface.
press HOME "backgrounded"
sleep 2
launch "resumed"
assert_running "after_resume"

# Rotation shakes out layout crashes cheaply.
idb ui rotate landscape 2>/dev/null || echo "(rotate unsupported, skipping)"
sleep 2
send_step "landscape"
idb ui rotate portrait 2>/dev/null || true
sleep 2
send_step "portrait"

assert_running "final"
echo "== smoke complete =="
