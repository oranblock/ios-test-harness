#!/usr/bin/env bash
# Full screen sweep: launch every screen the app can be launched into, prove each
# one survives, and photograph it.
#
# WHY NOT TAPS. Driving a menu blind needs coordinates, and coordinates are
# device-specific, layout-fragile, and silently wrong when a screen is slow — a
# tap that lands on nothing produces a screenshot of the previous screen and a
# green run. This app reads SKIRMISH_SCREEN at launch (SkirmishApp.swift:62), so
# every screen it names can be reached exactly, with no coordinates at all.
#
# It also side-steps the onboarding gate: an unrecognised value falls through to
# the hub, which is how you get past a first-run language picker without
# completing it.
#
# One screen per launch is deliberate. A crash then names itself instead of
# taking the rest of the sweep with it.

source "$(dirname "$0")/../scripts/lib.sh"

echo "== screen sweep: $BUNDLE_ID =="

# Recognised by the app's launch switch. `hub` is not a case — it falls through
# to the default, which is the hub, and that is the point.
visit hub            "hub"
visit forge          "forge"
visit cargo          "cargo"
visit fleet          "fleet"
visit saloon         "saloon"
visit exchange       "exchange"
visit battlebench    "battle_bench"
visit onboarding     "onboarding"

# Back to the hub at the end, so the last screenshot is the screen a tap-driven
# follow-up would start from. Read the grid coordinates off this one.
launch_screen hub    "hub_final_for_coordinates"

report_screens
echo "== sweep complete =="
