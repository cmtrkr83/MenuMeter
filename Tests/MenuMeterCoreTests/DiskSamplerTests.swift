import Testing
@testable import MenuMeterCore

@Suite struct DiskSamplerTests {
    @Test func usageCalculation() {
        let usage = DiskSampler.calculateUsage(blockCount: 1_000, freeBlocks: 400, blockSize: 4_096)
        #expect(usage?.used == 2_457_600)
        #expect(usage?.total == 4_096_000)
    }

    @Test func zeroBlocksReturnsNil() {
        #expect(DiskSampler.calculateUsage(blockCount: 0, freeBlocks: 0, blockSize: 4_096) == nil)
    }

    @Test func freeGreaterThanBlocksClampsUsedToZero() {
        let usage = DiskSampler.calculateUsage(blockCount: 100, freeBlocks: 150, blockSize: 4_096)
        #expect(usage?.used == 0)
        #expect(usage?.total == 409_600)
    }

    @Test func blockSizeOverflowReturnsNil() {
        #expect(DiskSampler.calculateUsage(blockCount: UInt64.max, freeBlocks: 0, blockSize: 4_096) == nil)
    }
}
