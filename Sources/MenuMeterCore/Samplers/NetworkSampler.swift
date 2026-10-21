import Darwin
import Foundation

public struct NetworkCounters: Equatable, Sendable {
    public let received: UInt64
    public let sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public final class NetworkSampler: @unchecked Sendable {
    private var previousCounters: NetworkCounters?
    private var previousTimestamp: TimeInterval?

    public init() {}

    public func sample() -> (down: Double, up: Double) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let current = Self.readCounters() else { return (0, 0) }

        let elapsed = previousTimestamp.map { timestamp - $0 } ?? 0
        let rates = Self.calculateRates(
            previous: previousCounters,
            current: current,
            elapsed: elapsed
        )

        previousCounters = current
        previousTimestamp = timestamp
        return rates
    }

    public static func calculateRates(
        previous: NetworkCounters?,
        current: NetworkCounters,
        elapsed: TimeInterval
    ) -> (down: Double, up: Double) {
        guard let previous, elapsed > 0 else { return (0, 0) }
        return (
            down: Double(delta(previous: previous.received, current: current.received)) / elapsed,
            up: Double(delta(previous: previous.sent, current: current.sent)) / elapsed
        )
    }

    public static func delta(previous: UInt64, current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    public static func isIncludedInterface(_ name: String) -> Bool {
        if name == "lo0" { return false }
        let excludedPrefixes = ["utun", "awdl", "llw", "bridge"]
        return !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    private static func readCounters() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }

        var received: UInt64 = 0
        var sent: UInt64 = 0

        buffer.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0

            while offset + MemoryLayout<if_msghdr>.stride <= length {
                let header = baseAddress
                    .advanced(by: offset)
                    .assumingMemoryBound(to: if_msghdr.self)
                    .pointee
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int(header.ifm_type) == Int(RTM_IFINFO2),
                   messageLength >= MemoryLayout<if_msghdr2>.stride {
                    let info = baseAddress
                        .advanced(by: offset)
                        .assumingMemoryBound(to: if_msghdr2.self)
                        .pointee

                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if isIncludedInterface(name) {
                            received &+= info.ifm_data.ifi_ibytes
                            sent &+= info.ifm_data.ifi_obytes
                        }
                    }
                }

                offset += messageLength
            }
        }

        return NetworkCounters(received: received, sent: sent)
    }
}
