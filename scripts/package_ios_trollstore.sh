#!/usr/bin/env bash

set -euo pipefail

usage() {
    printf 'Usage: %s <Runner.app> <output.ipa> [--entitlements <file>]\n' "$0" >&2
}

fail() {
    printf 'TrollStore IPA packaging failed: %s\n' "$1" >&2
    exit 1
}

[[ "$#" -eq 2 || "$#" -eq 4 ]] || {
    usage
    exit 64
}

source_app="$1"
output_ipa="$2"
declared_entitlements=""

if [[ "$#" -eq 4 ]]; then
    [[ "$3" == "--entitlements" ]] || {
        usage
        exit 64
    }
    declared_entitlements="$4"
fi

[[ "$(uname -s)" == "Darwin" ]] || fail "this script requires macOS codesign"
[[ -d "$source_app" && "$source_app" == *.app ]] ||
    fail "input must be an existing .app bundle"
[[ "$output_ipa" == *.ipa ]] || fail "output must use the .ipa extension"
[[ ! -e "$output_ipa" ]] || fail "refusing to overwrite existing output: $output_ipa"

for required_command in codesign file find plutil zip; do
    command -v "$required_command" >/dev/null 2>&1 ||
        fail "required command is unavailable: $required_command"
done

if [[ -n "$declared_entitlements" ]]; then
    [[ -f "$declared_entitlements" ]] ||
        fail "declared entitlements file does not exist: $declared_entitlements"
    plutil -lint "$declared_entitlements" >/dev/null ||
        fail "declared entitlements are not a valid plist"
fi

source_app="$(cd "$(dirname "$source_app")" && pwd -P)/$(basename "$source_app")"
output_parent="$(dirname "$output_ipa")"
mkdir -p "$output_parent"
output_parent="$(cd "$output_parent" && pwd -P)"
output_ipa="$output_parent/$(basename "$output_ipa")"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/simple-live-trollstore.XXXXXX")"
payload_dir="$temporary_root/Payload"
staged_app="$payload_dir/$(basename "$source_app")"
entitlements_manifest="$temporary_root/nested-entitlements.tsv"
app_entitlements="$temporary_root/app-entitlements.plist"
output_created=0

cleanup() {
    local status="$?"

    if [[ "$status" -ne 0 && "$output_created" -eq 1 ]]; then
        rm -f "$output_ipa"
    fi
    rm -rf "$temporary_root"
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$payload_dir"
cp -R "$source_app" "$staged_app"
if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$staged_app"
fi
: >"$entitlements_manifest"

extract_entitlements() {
    local signed_code="$1"
    local destination="$2"

    rm -f "$destination"
    if codesign -d --entitlements :- "$signed_code" >"$destination" 2>/dev/null &&
        [[ -s "$destination" ]] &&
        plutil -lint "$destination" >/dev/null 2>&1; then
        return 0
    fi

    rm -f "$destination"
    return 1
}

sign_adhoc() {
    local code="$1"
    local entitlements="${2:-}"
    local codesign_args=(--force --sign - --timestamp=none --generate-entitlement-der)

    if [[ -n "$entitlements" ]]; then
        codesign_args+=(--entitlements "$entitlements")
    fi
    codesign "${codesign_args[@]}" "$code"
}

entitlements_for_bundle() {
    local requested_bundle="$1"
    local bundle=""
    local entitlements=""

    while IFS=$'\t' read -r bundle entitlements; do
        if [[ "$bundle" == "$requested_bundle" ]]; then
            printf '%s\n' "$entitlements"
            return 0
        fi
    done <"$entitlements_manifest"

    return 1
}

# Capture entitlements before touching any executable: they live in its existing
# signature and would otherwise be lost during the inner signing pass.
if ! extract_entitlements "$staged_app" "$app_entitlements"; then
    if [[ -n "$declared_entitlements" ]]; then
        cp "$declared_entitlements" "$app_entitlements"
    else
        rm -f "$app_entitlements"
    fi
fi

while IFS= read -r bundle; do
    [[ "$bundle" == "$staged_app" ]] && continue
    nested_entitlements="$(mktemp "$temporary_root/entitlements.XXXXXX")"
    if extract_entitlements "$bundle" "$nested_entitlements"; then
        printf '%s\t%s\n' "$bundle" "$nested_entitlements" >>"$entitlements_manifest"
    else
        rm -f "$nested_entitlements"
    fi
done < <(
    find "$staged_app" -depth -type d \
        \( -name '*.framework' -o -name '*.appex' -o -name '*.xpc' -o -name '*.app' \) \
        -print
)

# Sign every embedded Mach-O first. Bundle containers are signed in a separate
# depth-first pass below, and the outer application is always signed last.
while IFS= read -r candidate; do
    if file -b "$candidate" | grep -q 'Mach-O'; then
        sign_adhoc "$candidate"
    fi
done < <(find "$staged_app" -depth -type f -print)

while IFS= read -r bundle; do
    [[ "$bundle" == "$staged_app" ]] && continue
    preserved_entitlements=""
    preserved_entitlements="$(entitlements_for_bundle "$bundle" || true)"
    sign_adhoc "$bundle" "$preserved_entitlements"
done < <(
    find "$staged_app" -depth -type d \
        \( -name '*.framework' -o -name '*.appex' -o -name '*.xpc' -o -name '*.app' \) \
        -print
)

app_entitlements_to_sign=""
if [[ -f "$app_entitlements" ]]; then
    app_entitlements_to_sign="$app_entitlements"
fi
sign_adhoc "$staged_app" "$app_entitlements_to_sign"

while IFS= read -r signed_code; do
    codesign --verify --strict --verbose=2 "$signed_code"
done < <(
    find "$staged_app" -depth \
        \( -type f -o -type d \) \
        \( -name '*.dylib' -o -name '*.framework' -o -name '*.appex' -o -name '*.xpc' -o -name '*.app' \) \
        -print
)

# ZIP member order, timestamps, symlinks, and extra metadata are normalized so
# identical signed application inputs produce identical IPA archives.
find "$payload_dir" -depth -exec touch -h -t 198001010000 {} +
output_created=1
(
    cd "$temporary_root"
    find Payload -print | LC_ALL=C sort | zip -X -y -q "$output_ipa" -@
)

printf 'Created TrollStore IPA: %s\n' "$output_ipa"
