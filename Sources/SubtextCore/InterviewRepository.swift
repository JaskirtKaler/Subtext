import Foundation

/// An on-device JSON index. Loading failures are surfaced to the caller, so a
/// corrupt index is never mistaken for an empty library and overwritten.
public struct InterviewRepository: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> [Interview] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder().decode([Interview].self, from: data)
    }

    public func save(_ interviews: [Interview]) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(interviews)
        try data.write(to: indexURL, options: .atomic)
    }

    /// The filename is treated as a single path component, preventing a saved
    /// value from directing playback outside this repository's directory.
    public func audioURL(filename: String) -> URL {
        let component = (filename as NSString).lastPathComponent
        let safeComponent = component.isEmpty || component == "." || component == ".."
            ? "recording.m4a"
            : component
        return directory.appendingPathComponent(safeComponent, isDirectory: false)
    }

    private var indexURL: URL {
        directory.appendingPathComponent("interviews.json", isDirectory: false)
    }
}
