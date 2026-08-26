#!/usr/bin/env bash

set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly lib_mpv="$repository_root/lib/modules/live_room/player/lib_mpv.dart"

fail() {
    printf 'iOS PiP background playback verification failed: %s\n' "$1" >&2
    exit 1
}

[[ -f "$lib_mpv" ]] || fail "missing lib_mpv.dart"

grep -Eq 'Platform\.isIOS[[:space:]]*\?[[:space:]]*false[[:space:]]*:[[:space:]]*settings\.playerAutoPause\.value' \
    "$lib_mpv" || fail "iOS must not auto-pause mpv when the app backgrounds"
grep -Eq 'pauseUponEnteringBackgroundMode:[[:space:]]*autoPauseOnBackground' \
    "$lib_mpv" || fail "Video pause-on-background policy is not wired"
grep -Eq 'resumeUponEnteringForegroundMode:[[:space:]]*autoPauseOnBackground' \
    "$lib_mpv" || fail "Video resume-on-foreground policy is not paired"

printf 'iOS PiP background playback static verification passed.\n'
