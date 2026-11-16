#!/bin/bash
# Installs the last built Simulator app over the existing copy, preserving data.
set -euo pipefail
project_directory="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
simulator_app="$project_directory/.build-results/DerivedData/Build/Products/Debug-iphonesimulator/Subtext.app"
mkdir -p "$project_directory/.build-results"
exec > >(/usr/bin/tee "$project_directory/.build-results/user-simulator-install.log") 2>&1

installation_failed() {
    printf '\nSubtext could not start. Open an iPhone simulator and retry this launcher from Finder. The error above explains where it stopped.\n' >&2
    if [[ -t 0 ]]; then
        read -r -p 'Press Return to close… ' ignored_response || true
    fi
}
trap installation_failed ERR

if [[ ! -f "$simulator_app/Info.plist" || ! -f "$simulator_app/Subtext" ]]; then
    printf 'No built Simulator app was found. Build the Subtext scheme for an iPhone simulator in Xcode first.\n' >&2
    exit 1
fi
/bin/bash "$project_directory/scripts/validate-firebase-config.sh" "$simulator_app/GoogleService-Info.plist" com.jaskirtkaler.Subtext
expected_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$simulator_app/Info.plist")"
printf 'Installing rebuilt Subtext build %s. Existing recordings are preserved.\n' "$expected_build"
/usr/bin/xcrun simctl install booted "$simulator_app"
installed_app="$(/usr/bin/xcrun simctl get_app_container booted com.jaskirtkaler.Subtext app)"
installed_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$installed_app/Info.plist")"
if [[ "$installed_build" != "$expected_build" || ! -f "$installed_app/GoogleService-Info.plist" ]]; then
    printf 'The installed app did not match the rebuilt app. Installation was not verified.\n' >&2
    installation_failed
    exit 1
fi
# Restart the installed app so an already-running old process cannot be reused.
/usr/bin/xcrun simctl launch --terminate-running-process booted com.jaskirtkaler.Subtext
printf '\nVerified installed Subtext build %s and requested launch. Open Settings & privacy to test the AI connection.\n' "$installed_build"
