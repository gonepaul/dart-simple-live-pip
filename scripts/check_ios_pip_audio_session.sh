#!/usr/bin/env bash

set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly info_plist="$repository_root/ios/Runner/Info.plist"
readonly app_delegate="$repository_root/ios/Runner/AppDelegate.swift"

fail() {
    printf 'iOS PiP audio-session verification failed: %s\n' "$1" >&2
    exit 1
}

require_regex() {
    local pattern="$1"
    local file="$2"
    local description="$3"

    grep -Eq -- "$pattern" "$file" || fail "$description"
}

[[ -f "$info_plist" ]] || fail "missing ios/Runner/Info.plist"
[[ -f "$app_delegate" ]] || fail "missing ios/Runner/AppDelegate.swift"
command -v python3 >/dev/null 2>&1 || fail "python3 is required to inspect Info.plist"

python3 - "$info_plist" <<'PY' || fail "Info.plist must declare audio in UIBackgroundModes"
import plistlib
import sys

with open(sys.argv[1], "rb") as plist_file:
    plist = plistlib.load(plist_file)

background_modes = plist.get("UIBackgroundModes", [])
if not isinstance(background_modes, list) or "audio" not in background_modes:
    raise SystemExit(1)
PY

require_regex '^import AVFoundation$' "$app_delegate" \
    "AppDelegate must import AVFoundation"
require_regex 'AVAudioSession\.sharedInstance\(\)' "$app_delegate" \
    "AppDelegate must use the shared AVAudioSession"
require_regex 'setCategory\(\.playback,[[:space:]]*mode:[[:space:]]*\.moviePlayback\)' \
    "$app_delegate" \
    "AppDelegate must set the playback category and moviePlayback mode"
require_regex 'setActive\(true\)' "$app_delegate" \
    "AppDelegate must activate the audio session"
require_regex 'AVAudioSession\.interruptionNotification' "$app_delegate" \
    "AppDelegate must observe audio-session interruptions"
require_regex 'AVAudioSessionInterruptionOptionKey' "$app_delegate" \
    "AppDelegate must inspect interruption resume options"
require_regex '\.shouldResume' "$app_delegate" \
    "AppDelegate must reactivate only when an interruption requests resume"
require_regex 'AVAudioSession\.mediaServicesWereResetNotification' "$app_delegate" \
    "AppDelegate must observe media-services resets"
require_regex 'removeObserver\(' "$app_delegate" \
    "AppDelegate must safely remove its notification observers"

printf 'iOS PiP audio-session static verification passed.\n'
