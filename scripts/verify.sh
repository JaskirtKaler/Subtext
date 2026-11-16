#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
task_root="$(cd "$script_dir/.." && pwd)"
cd "$task_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$task_root/.build-results/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build-results/SwiftModuleCache"
mkdir -p .build-results
swift_option=""
xcode_options=(-packageCachePath "$task_root/.build-results/PackageCache" -clonedSourcePackagesDirPath "$task_root/.build-results/SourcePackages" -skipPackageUpdates)
# This is only needed inside environments that cannot nest a compiler sandbox.
if [[ "${SUBTEXT_NESTED_SANDBOX:-0}" == "1" ]]; then
    swift_option="--disable-sandbox"
    xcode_options+=('OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' -IDEDisablePackageManifestCaching=YES -IDEPackageSupportDisableManifestSandbox=YES "-IDEPackageCacheDirPath=$task_root/.build-results/PackageCache")
fi
trap 'printf "Verification stopped. Inspect .build-results/*.log for the failure.\n" >&2' ERR
printf 'Running model, storage, and AI validation tests…\n'
swift test ${swift_option:+"$swift_option"} --scratch-path .build --cache-path .build-results/SwiftPMCache --config-path .build-results/SwiftPMConfig --security-path .build-results/SwiftPMSecurity > .build-results/swift-test.log 2>&1
printf 'Running AppModel state workflows with an unavailable microphone adapter…\n'
"$script_dir/test-workflows.sh" > .build-results/workflow-test-run.log 2>&1
printf 'Building the iPhone Simulator app and test bundles…\n'
"$DEVELOPER_DIR/usr/bin/xcodebuild" -project Subtext.xcodeproj -scheme Subtext -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build-results/DerivedData CODE_SIGNING_ALLOWED=NO "${xcode_options[@]}" build-for-testing > .build-results/xcode-test-build.log 2>&1
printf 'Building the iPhone Release app…\n'
"$DEVELOPER_DIR/usr/bin/xcodebuild" -project Subtext.xcodeproj -scheme Subtext -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build-results/DerivedData CODE_SIGNING_ALLOWED=NO "${xcode_options[@]}" build > .build-results/xcode-release-device-build.log 2>&1
python3 - <<'PY'
import plistlib
import re
from pathlib import Path
for configuration in ('Debug-iphonesimulator', 'Release-iphoneos'):
    path = Path('.build-results/DerivedData/Build/Products') / configuration / 'Subtext.app/Info.plist'
    with path.open('rb') as stream:
        info = plistlib.load(stream)
    assert info['UIDeviceFamily'] == [1], (configuration, info.get('UIDeviceFamily'))
    assert info['MinimumOSVersion'] == '17.0', (configuration, info.get('MinimumOSVersion'))
def executed_count(path):
    matches = re.findall(
        r"Test Suite '([^']+\.xctest)' passed[^\n]*\n\s*Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures",
        Path(path).read_text(),
    )
    suites = {name: (int(total), int(skipped or 0), int(failures)) for name, total, skipped, failures in matches}
    assert suites, f'No completed XCTest suites found in {path}'
    assert all(failures == 0 for _, _, failures in suites.values()), f'Failed tests in {path}'
    return sum(total - skipped for total, skipped, _ in suites.values()), sum(skipped for _, skipped, _ in suites.values())
portable, portable_skipped = executed_count('.build-results/swift-test.log')
workflows, workflows_skipped = executed_count('.build-results/WorkflowHost/test.log')
print(f'Passed: {portable} portable/media tests + {workflows} model/state tests = {portable + workflows} executed tests.')
print(f'Skipped: {portable_skipped + workflows_skipped} host-specific tests; skipped cases are excluded from the executed count.')
print('Passed: both phone builds, unit/UI test-bundle compilation, iPhone-only deployment checks.')
PY
