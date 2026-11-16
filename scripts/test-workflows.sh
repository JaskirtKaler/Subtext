#!/bin/bash
# Runs the real AppModel state machine on macOS with an explicitly unavailable
# microphone adapter. These are model/state tests, not UI or recording tests.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
task_root="$(cd "$script_dir/.." && pwd)"
cd "$task_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$task_root/.build-results/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_root/.build-results/SwiftModuleCache"
host_root="$task_root/.build-results/WorkflowHost"
mkdir -p "$host_root"

python3 - "$task_root" "$host_root" <<'PY'
import hashlib
import json
from pathlib import Path
import shutil
import sys

root, host = map(Path, sys.argv[1:])
sources = host / 'Sources/Subtext'
tests = host / 'Tests/WorkflowTests'
sources.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
checksums = {}
for generated in sources.glob('*.swift'):
    generated.unlink()
source_files = [root / 'Subtext/AppModel.swift', root / 'Subtext/Services/CloudReviewService.swift',
                *sorted((root / 'Subtext/Services').glob('Speech*.swift'))]
for original in source_files:
    relative = str(original.relative_to(root))
    copied = sources / original.name
    shutil.copyfile(original, copied)
    assert original.read_bytes() == copied.read_bytes()
    checksums[relative] = hashlib.sha256(copied.read_bytes()).hexdigest()
shutil.copyfile(root / 'SubtextTests/AppModelWorkflowTests.swift', tests / 'AppModelWorkflowTests.swift')
(host / 'source-checksums.json').write_text(json.dumps(checksums, indent=2))
(host / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SubtextWorkflowHost",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "SubtextCore", path: ROOT)],
    targets: [
        .target(name: "Subtext", dependencies: [.product(name: "SubtextCore", package: "SubtextCore")]),
        .testTarget(name: "WorkflowTests", dependencies: ["Subtext", .product(name: "SubtextCore", package: "SubtextCore")])
    ],
    swiftLanguageModes: [.v5]
)
'''.replace('ROOT', json.dumps(str(root))))
(sources / 'UnavailableMicrophoneAdapter.swift').write_text('''import Foundation
import Observation

// Test-only adapter: every operation that would touch microphone capture or
// recorder recovery metadata fails explicitly. No recording implementation is
// reproduced here. AppModel still scans real synthetic audio through AVFoundation.
struct RecordedAudio: Sendable { let filename: String; let duration: Double }
enum MicrophoneAdapterError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Microphone and recorder metadata are unavailable in the native state-test host." }
}
@MainActor @Observable
final class AudioRecorder {
    let isRecording = false
    let isPaused = false
    let elapsed: TimeInterval = 0
    let levels: [Float] = []
    let inputName = "Unavailable microphone (state tests)"
    var activeFilename: String? { nil }
    var errorMessage: String?
    init(directory: URL) {}
    func start() async throws -> String { throw MicrophoneAdapterError.unavailable }
    func pause() {}
    func resume() throws { throw MicrophoneAdapterError.unavailable }
    func finish() throws -> RecordedAudio { throw MicrophoneAdapterError.unavailable }
    func keepFileAndClose() -> RecordedAudio? { nil }
    func addBookmarkTime() -> TimeInterval { 0 }
    static func recoverableRecording(in directory: URL) throws -> RecordedAudio? { throw MicrophoneAdapterError.unavailable }
    static func clearRecoveryMetadata(in directory: URL) throws { throw MicrophoneAdapterError.unavailable }
}
''')
print('Prepared exact AppModel/Cloud/Speech sources with test-only unavailable microphone adapter.')
PY

swift_options=()
if [[ "${SUBTEXT_NESTED_SANDBOX:-0}" == "1" ]]; then
    swift_options+=(--disable-sandbox)
fi
printf 'Running native model/state workflow tests…\n'
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test --package-path "$host_root" --scratch-path "$host_root/Build" --cache-path "$task_root/.build-results/SwiftPMCache" --config-path "$task_root/.build-results/SwiftPMConfig" --security-path "$task_root/.build-results/SwiftPMSecurity" "${swift_options[@]}" > "$host_root/test.log" 2>&1
printf 'Model/state workflow tests passed. Results: .build-results/WorkflowHost/test.log\n'
