import Foundation

public enum Metric: String, CaseIterable, Sendable {
    case cpu
    case ram
    case network
    case disk
    case gpu
}

public enum MetricRotation {
    public static let order: [Metric] = [.cpu, .ram, .network, .disk, .gpu]

    public static func next(after metric: Metric) -> Metric {
        guard let index = order.firstIndex(of: metric) else { return .cpu }
        return order[(index + 1) % order.count]
    }
}
