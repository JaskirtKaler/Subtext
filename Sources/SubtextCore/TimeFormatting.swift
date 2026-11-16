import Foundation

public enum TimeFormatting {
    /// A playback timestamp, rounded down to a whole second. Invalid and
    /// negative values display as zero. Hour-long sessions include hours.
    public static func timestamp(_ seconds: TimeInterval, includeHours: Bool = false) -> String {
        let total = wholeSeconds(seconds)
        let second = total % 60
        let minute = (total / 60) % 60
        let hour = total / 3_600

        if includeHours || hour > 0 {
            return "\(hour):\(padded(minute)):\(padded(second))"
        }
        return "\(padded(total / 60)):\(padded(second))"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        timestamp(seconds)
    }

    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        guard seconds < Double(Int.max) else { return Int.max }
        return Int(seconds.rounded(.down))
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
