import Darwin
import Foundation

public final class DiskSampler {
    public init() {}

    public func sample() -> (used: UInt64, total: UInt64)? {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return nil }
        return Self.calculateUsage(
            blockCount: UInt64(stats.f_blocks),
            freeBlocks: UInt64(stats.f_bfree),
            blockSize: UInt64(stats.f_bsize)
        )
    }

    public static func calculateUsage(
        blockCount: UInt64,
        freeBlocks: UInt64,
        blockSize: UInt64
    ) -> (used: UInt64, total: UInt64)? {
        guard blockCount > 0, blockSize > 0 else { return nil }

        let (total, totalOverflow) = blockCount.multipliedReportingOverflow(by: blockSize)
        guard !totalOverflow else { return nil }

        let usedBlocks = blockCount > freeBlocks ? blockCount - freeBlocks : 0
        let (used, usedOverflow) = usedBlocks.multipliedReportingOverflow(by: blockSize)
        guard !usedOverflow else { return nil }

        return (used, total)
    }
}
