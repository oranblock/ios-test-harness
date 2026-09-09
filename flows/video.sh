#!/usr/bin/env bash
# Film the live menu. A screenshot proves a screen drew once; only a clip shows
# whether the SceneKit particle swarm and wave mesh are actually animating.
#
# Hub only, deliberately: the Filament screens (saloon, battlebench) abort on the
# simulator inside MTLSimDriver's newArgumentEncoderWithLayout:, so there is
# nothing to film there until this runs on a device.
source "$(dirname "$0")/../scripts/lib.sh"

echo "== video: $BUNDLE_ID =="

launch_screen hub "hub_before_clip"
sleep 2                      # let the particle system reach steady state
record_clip "${CLIP_SECONDS:-3}" "hub_scenekit"
assert_running "after_recording"

echo "== video complete =="
