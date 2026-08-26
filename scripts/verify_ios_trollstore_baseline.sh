#!/usr/bin/env bash

set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly workflow="$repository_root/.github/workflows/ios-trollstore.yaml"
readonly packager="$repository_root/scripts/package_ios_trollstore.sh"

fail() {
    printf 'iOS TrollStore baseline verification failed: %s\n' "$1" >&2
    exit 1
}

require_regex() {
    local pattern="$1"
    local file="$2"
    local description="$3"

    grep -Eq -- "$pattern" "$file" || fail "$description"
}

reject_regex() {
    local pattern="$1"
    local file="$2"
    local description="$3"

    if grep -Eiq -- "$pattern" "$file"; then
        fail "$description"
    fi
}

[[ -f "$workflow" ]] || fail "missing .github/workflows/ios-trollstore.yaml"
[[ -f "$packager" ]] || fail "missing scripts/package_ios_trollstore.sh"

bash -n "$packager"

mapfile -t workflow_events < <(
    awk '
        /^on:$/ { in_on = 1; next }
        in_on && /^[^[:space:]]/ { exit }
        in_on && /^    [[:alnum:]_-]+:$/ {
            event = $1
            sub(/:$/, "", event)
            print event
        }
    ' "$workflow"
)

[[ "${#workflow_events[@]}" -eq 1 ]] ||
    fail "workflow must declare exactly one trigger"
[[ "${workflow_events[0]}" == "workflow_dispatch" ]] ||
    fail "workflow trigger must be workflow_dispatch"

require_regex '^permissions:$' "$workflow" "workflow must set explicit permissions"
require_regex '^    contents: read$' "$workflow" "workflow permissions must be contents: read"
require_regex '^        runs-on: macos-' "$workflow" "workflow must build on macOS"
require_regex 'flutter build ios --release --no-codesign' "$workflow" \
    "workflow must use Flutter no-codesign iOS release build"
require_regex 'scripts/package_ios_trollstore\.sh' "$workflow" \
    "workflow must invoke the TrollStore packager"
require_regex 'uses: actions/upload-artifact@' "$workflow" \
    "workflow must upload an artifact"
require_regex 'name: .*TrollStore' "$workflow" \
    "uploaded artifact name must contain TrollStore"
require_regex 'path: .*TrollStore.*\.ipa' "$workflow" \
    "uploaded IPA path must contain TrollStore"

reject_regex 'secrets\.' "$workflow" "workflow must not consume repository secrets"
reject_regex '(p12|mobileprovision|provisioning profile|certificate)' "$workflow" \
    "workflow must not install certificates or provisioning profiles"
reject_regex 'security[[:space:]]+(import|create-keychain|unlock-keychain)' "$workflow" \
    "workflow must not mutate a signing keychain"
reject_regex '(DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|application-identifier)' "$workflow" \
    "workflow must not invent signing or application identifiers"

require_regex '^set -euo pipefail$' "$packager" "packager must use strict shell mode"
require_regex 'codesign -d --entitlements :-' "$packager" \
    "packager must extract existing signed entitlements"
require_regex '--entitlements' "$packager" \
    "packager must reuse preserved entitlements when signing"
require_regex 'find .* -depth' "$packager" \
    "packager must traverse nested code from the inside out"
require_regex '--sign -' "$packager" "packager must use ad-hoc signing"
require_regex '--timestamp=none' "$packager" \
    "packager must disable remote signing timestamps"
require_regex 'LC_ALL=C sort' "$packager" \
    "packager must sort archive members deterministically"
require_regex 'zip .*-[^[:space:]]*X' "$packager" \
    "packager must omit extra ZIP metadata"
require_regex 'touch .*198001010000' "$packager" \
    "packager must normalize archive member timestamps"

reject_regex 'codesign.*--sign.*--deep|codesign.*--deep.*--sign' "$packager" \
    "packager must sign nested code explicitly instead of using codesign --deep"
reject_regex '(application-identifier|com\.apple\.developer\.team-identifier|TeamIdentifier)' "$packager" \
    "packager must never synthesize team or application identifier entitlements"

printf 'iOS TrollStore baseline static verification passed.\n'
