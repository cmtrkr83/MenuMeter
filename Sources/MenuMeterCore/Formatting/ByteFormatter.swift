import Foundation

public enum ByteFormatter {
    private static let units = ["B", "K", "M", "G", "T", "P"]

    public static func bytes(_ value: UInt64) -> String {
        format(Double(value))
    }

    public static func byteRate(_ bytesPerSecond: Double) -> String {
        format(bytesPerSecond)
    }

    public static func detailRate(_ bytesPerSecond: Double) -> String {
        byteRate(bytesPerSecond) + "/s"
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0B" }
        if value < 1024 {
            return "\(Int(value.rounded()))B"
        }

        var scaled = value
        var unitIndex = 0
        while scaled >= 1024, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f%@", scaled, units[unitIndex])
    }
}
