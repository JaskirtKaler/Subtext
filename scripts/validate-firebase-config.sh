#!/bin/bash
# Validates the packaged app configuration without printing configuration values.
set -euo pipefail
configuration_file="${1:?Expected the packaged GoogleService-Info.plist path}"
app_bundle_id="${2:?Expected the app bundle identifier}"
if [[ ! -f "$configuration_file" ]]; then
    printf 'error: Subtext requires GoogleService-Info.plist in the app bundle. Add the Firebase iOS configuration to the Subtext target.\n' >&2
    exit 1
fi
if ! /usr/bin/plutil -lint "$configuration_file" > /dev/null 2>&1; then
    printf 'error: The packaged Firebase configuration is not a valid property list.\n' >&2
    exit 1
fi
configured_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$configuration_file" 2>/dev/null || true)"
if [[ "$configured_bundle_id" != "$app_bundle_id" ]]; then
    printf 'error: The packaged Firebase configuration belongs to a different iOS app. Download the matching configuration from Firebase Console.\n' >&2
    exit 1
fi
for required_key in GOOGLE_APP_ID PROJECT_ID API_KEY; do
    configured_value="$(/usr/libexec/PlistBuddy -c "Print :$required_key" "$configuration_file" 2>/dev/null || true)"
    if [[ -z "$configured_value" ]]; then
        printf 'error: The packaged Firebase configuration is incomplete. Download a fresh iOS configuration from Firebase Console.\n' >&2
        exit 1
    fi
done
printf 'Firebase iOS configuration is packaged and matches this app.\n'
