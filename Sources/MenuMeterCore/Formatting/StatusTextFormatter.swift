import Foundation

public enum StatusTextFormatter {
    private static let bytesPerGiB = 1_073_741_824.0

    public static func shortLabel(for metric: Metric) -> String {
        switch metric {
        case .cpu:
            return "CPU"
        case .ram:
            return "RAM"
        case .network:
            return "AĞ"
        case .disk:
            return "SSD"
        case .gpu:
            return "GPU"
        }
    }

    public static func menuBarValue(for metric: Metric, snapshot: MetricsSnapshot) -> String {
        switch metric {
        case .cpu:
            return "\(percent(snapshot.cpu))%"
        case .ram:
            return ByteFormatter.bytes(snapshot.ramUsed)
        case .network:
            return "↓\(ByteFormatter.byteRate(snapshot.networkDown)) ↑\(ByteFormatter.byteRate(snapshot.networkUp))"
        case .disk:
            return "\(percent(snapshot.diskFraction))%"
        case .gpu:
            guard let gpu = snapshot.gpu else { return "—" }
            return "\(percent(gpu))%"
        }
    }

    public static func detailLines(for snapshot: MetricsSnapshot) -> [String] {
        let freeBytes = snapshot.diskTotal > snapshot.diskUsed
            ? snapshot.diskTotal - snapshot.diskUsed
            : 0

        return [
            "CPU \(percent(snapshot.cpu))%",
            "RAM \(gigabytes(snapshot.ramUsed)) / \(gigabytes(snapshot.ramTotal)) GB",
            "Ağ ↓\(ByteFormatter.detailRate(snapshot.networkDown)) ↑\(ByteFormatter.detailRate(snapshot.networkUp))",
            "SSD \(percent(snapshot.diskFraction))% (boş \(gigabytes(freeBytes)) GB)",
            snapshot.gpu.map { "GPU \(percent($0))%" } ?? "GPU kullanılamıyor",
        ]
    }

    public static func accessibilityLabel(for metric: Metric, snapshot: MetricsSnapshot) -> String {
        switch metric {
        case .cpu:
            return "CPU kullanımı yüzde \(percent(snapshot.cpu))"
        case .ram:
            return "RAM kullanımı \(gigabytes(snapshot.ramUsed)) GB"
        case .network:
            return "Ağ indirme \(ByteFormatter.byteRate(snapshot.networkDown)), yükleme \(ByteFormatter.byteRate(snapshot.networkUp))"
        case .disk:
            return "SSD doluluğu yüzde \(percent(snapshot.diskFraction))"
        case .gpu:
            return snapshot.gpu.map { "GPU kullanımı yüzde \(percent($0))" } ?? "GPU kullanılamıyor"
        }
    }

    private static func percent(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * 100).rounded())
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / bytesPerGiB)
    }
}
