#!/bin/bash
# A temporary Mac Catalyst host for XCTest diagnostics. The shipping project
# remains iPhone-only. This does not establish iPhone UI or microphone behavior.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
task_root="$(cd "$script_dir/.." && pwd)"
cd "$task_root"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$task_root/.build-results/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build-results/SwiftModuleCache"
host_root="$task_root/.build-results/MacHost"
mkdir -p "$host_root"
case "${1:-}" in
    ""|--prepare-only|--show-destinations) ;;
    *) printf 'Usage: scripts/test-mac-host.sh [--prepare-only|--show-destinations]\n' >&2; exit 2 ;;
esac
trap 'printf "Mac test-host diagnostic stopped. Inspect .build-results/MacHost/*.log.\n" >&2' ERR

python3 - "$task_root" "$host_root" <<'PY'
import json
from pathlib import Path
import shutil
import sys

root, host = map(Path, sys.argv[1:])
source = root / 'Subtext.xcodeproj'
destination = host / 'Subtext.xcodeproj'
destination.mkdir(parents=True, exist_ok=True)
project = (source / 'project.pbxproj').read_text()
assert 'SUPPORTS_MACCATALYST = NO;' in project
assert 'TARGETED_DEVICE_FAMILY = 1;' in project
project = project.replace('SUPPORTS_MACCATALYST = NO;', 'SUPPORTS_MACCATALYST = YES;')
project = project.replace('TARGETED_DEVICE_FAMILY = 1;', 'TARGETED_DEVICE_FAMILY = "1,2";')
project = project.replace('projectDirPath = "";', f'projectDirPath = {json.dumps(str(root))};')
(destination / 'project.pbxproj').write_text(project)
for relative in (
    'project.xcworkspace/contents.xcworkspacedata',
    'project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
    'xcshareddata/xcschemes/Subtext.xcscheme',
):
    original = source / relative
    if original.is_file():
        copied = destination / relative
        copied.parent.mkdir(parents=True, exist_ok=True)
        if relative.endswith('.xcscheme'):
            scheme = original.read_text().replace('container:Subtext.xcodeproj',
                                                   'container:' + str(destination))
            copied.write_text(scheme)
        else:
            shutil.copyfile(original, copied)
print('Prepared temporary Mac Catalyst XCTest host in .build-results/MacHost.')
PY

if [[ "${1:-}" == "--prepare-only" ]]; then
    exit 0
fi

xcode_options=(-packageCachePath "$task_root/.build-results/PackageCache" -clonedSourcePackagesDirPath "$task_root/.build-results/SourcePackages" -skipPackageUpdates)
if [[ "${SUBTEXT_NESTED_SANDBOX:-0}" == "1" ]]; then
    xcode_options+=('OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' -IDEDisablePackageManifestCaching=YES -IDEPackageSupportDisableManifestSandbox=YES "-IDEPackageCacheDirPath=$task_root/.build-results/PackageCache")
fi

if [[ "${1:-}" == "--show-destinations" ]]; then
    "$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$host_root/Subtext.xcodeproj" -scheme Subtext -sdk macosx -derivedDataPath "$host_root/DerivedData" "${xcode_options[@]}" -showdestinations > "$host_root/destinations.log" 2>&1
    cat "$host_root/destinations.log"
    exit 0
fi

printf 'Running app-hosted unit tests in the temporary Mac Catalyst host…\n'
"$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$host_root/Subtext.xcodeproj" -scheme Subtext -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -destination-timeout 10 -derivedDataPath "$host_root/DerivedData" -resultBundlePath "$host_root/TestResults-$(date +%Y%m%d-%H%M%S).xcresult" -parallel-testing-enabled NO -only-testing:SubtextTests ARCHS=arm64 CODE_SIGNING_ALLOWED=NO "${xcode_options[@]}" test > "$host_root/test.log" 2>&1
printf 'Mac Catalyst app-hosted tests passed. Results: .build-results/MacHost/test.log\n'
