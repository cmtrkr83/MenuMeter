import Darwin
import Foundation

public final class MemorySampler: @unchecked Sendable {
    public init() {}

    public func sample() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        let totalResult = sysctlbyname("hw.memsize", &total, &size, nil, 0)
        guard totalResult == 0, total > 0 else { return (0, 0) }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let statsResult = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard statsResult == KERN_SUCCESS else { return (0, total) }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(mach_host_self(), &pageSize)
        guard pageResult == KERN_SUCCESS, pageSize > 0 else { return (0, total) }

        let used = Self.calculateUsedBytes(
            active: UInt64(stats.active_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            speculative: UInt64(stats.speculative_count),
            pageSize: UInt64(pageSize),
            totalMemory: total
        )
        return (used, total)
    }

    public static func calculateUsedBytes(
        active: UInt64,
        wired: UInt64,
        compressed: UInt64,
        speculative: UInt64,
        pageSize: UInt64,
        totalMemory: UInt64
    ) -> UInt64 {
        guard totalMemory > 0, pageSize > 0 else { return 0 }

        var pages: UInt64 = 0
        for value in [active, wired, compressed, speculative] {
            let (sum, overflow) = pages.addingReportingOverflow(value)
            if overflow { return totalMemory }
            pages = sum
        }

        let (bytes, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        if overflow { return totalMemory }
        return min(totalMemory, bytes)
    }
}
