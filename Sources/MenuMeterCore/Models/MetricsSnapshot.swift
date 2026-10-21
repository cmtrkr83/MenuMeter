import Foundation

public struct MetricsSnapshot: Equatable, Sendable {
    public let cpu: Double
    public let ramUsed: UInt64
    public let ramTotal: UInt64
    public let networkDown: Double
    public let networkUp: Double
    public let diskUsed: UInt64
    public let diskTotal: UInt64
    public let gpu: Double?
    public let timestamp: Date

    public init(
        cpu: Double,
        ramUsed: UInt64,
        ramTotal: UInt64,
        networkDown: Double,
        networkUp: Double,
        diskUsed: UInt64,
        diskTotal: UInt64,
        gpu: Double?,
        timestamp: Date = Date()
    ) {
        self.cpu = max(0, min(1, cpu))
        self.ramUsed = ramUsed
        self.ramTotal = ramTotal
        self.networkDown = networkDown
        self.networkUp = networkUp
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.gpu = gpu.map { max(0, min(1, $0)) }
        self.timestamp = timestamp
    }

    public var ramFraction: Double {
        guard ramTotal > 0 else { return 0 }
        return min(1, Double(ramUsed) / Double(ramTotal))
    }

    public var diskFraction: Double {
        guard diskTotal > 0 else { return 0 }
        return min(1, Double(diskUsed) / Double(diskTotal))
    }
}
