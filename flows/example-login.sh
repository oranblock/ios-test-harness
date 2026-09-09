#!/usr/bin/env bash
# A worked example: copy this to flows/<yourproject>.sh and edit.
#
# Coordinates are in POINTS, not pixels, and they are specific to one device
# size. Get them from a first run: use flows/smoke.sh, open the screenshot from
# the artifact, and read the position off it. A coordinate that worked on an
# iPhone 16 will miss on an SE.
source "$(dirname "$0")/../scripts/lib.sh"

launch "app_launched"

tap 150 250 "tapped_email_field"
type_text "testuser@example.com" "typed_email"

tap 150 320 "tapped_password_field"
type_text "hunter2" "typed_password"

tap 200 400 "tapped_login"
sleep 3
send_step "after_login"

# A login that crashes the app is the bug you most want reported.
assert_running "login_survived"

swipe 200 600 200 200 "scrolled"
echo "== example complete =="
