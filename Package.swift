// xcode: set sdk=iOS

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SubtextCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SubtextCore", targets: ["SubtextCore"])
    ],
    targets: [
        .target(name: "SubtextCore"),
        .testTarget(name: "SubtextCoreTests", dependencies: ["SubtextCore"]),
        .target(
            name: "SubtextAIValidation",
            dependencies: ["SubtextCore"],
            path: "Subtext/Services",
            exclude: ["AudioRecorder.swift", "AudioPlayer.swift", "SpeechTranscriber.swift", "WaveformSampler.swift", "SpeechTranscriptionSupport.swift", "SpeechAudioChunker.swift"],
            sources: ["CloudReviewService.swift"]
        ),
        .testTarget(
            name: "SubtextAIValidationTests", dependencies: ["SubtextAIValidation"], path: "SubtextTests",
            exclude: ["AppModelWorkflowTests.swift", "LiveAIIntegrationTests.swift", "AudioPlayerTests.swift", "AudioRecorderRecoveryTests.swift", "AudioSpeechTranscriberTests.swift", "AudioWaveformTests.swift", "AudioSpeechSupportTests.swift", "AudioSpeechChunkerTests.swift"],
            sources: ["CloudReviewValidationTests.swift", "CloudPreflightTests.swift", "CloudStructuredReviewTests.swift"]
        ),
        .target(
            name: "SubtextAudioValidation", path: "Subtext/Services",
            exclude: ["CloudReviewService.swift", "AudioRecorder.swift", "AudioPlayer.swift", "SpeechTranscriber.swift", "SpeechTranscriptionSupport.swift", "SpeechAudioChunker.swift"],
            sources: ["WaveformSampler.swift"]
        ),
        .testTarget(
            name: "SubtextAudioValidationTests", dependencies: ["SubtextAudioValidation"], path: "SubtextTests",
            exclude: ["AppModelWorkflowTests.swift", "LiveAIIntegrationTests.swift", "AudioPlayerTests.swift", "AudioRecorderRecoveryTests.swift", "AudioSpeechTranscriberTests.swift", "CloudReviewValidationTests.swift", "CloudPreflightTests.swift", "CloudStructuredReviewTests.swift", "AudioSpeechSupportTests.swift", "AudioSpeechChunkerTests.swift"],
            sources: ["AudioWaveformTests.swift"]
        ),
        .target(
            name: "SubtextSpeechValidation", path: "Subtext/Services",
            exclude: ["CloudReviewService.swift", "AudioRecorder.swift", "AudioPlayer.swift", "WaveformSampler.swift"],
            sources: ["SpeechTranscriptionSupport.swift", "SpeechAudioChunker.swift", "SpeechTranscriber.swift"]
        ),
        .testTarget(
            name: "SubtextSpeechValidationTests", dependencies: ["SubtextSpeechValidation"], path: "SubtextTests",
            exclude: ["AppModelWorkflowTests.swift", "LiveAIIntegrationTests.swift", "AudioPlayerTests.swift", "AudioRecorderRecoveryTests.swift", "CloudReviewValidationTests.swift", "CloudPreflightTests.swift", "CloudStructuredReviewTests.swift", "AudioWaveformTests.swift"],
            sources: ["AudioSpeechSupportTests.swift", "AudioSpeechChunkerTests.swift", "AudioSpeechTranscriberTests.swift"]
        )
    ]
)
