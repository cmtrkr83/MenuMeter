import Testing
@testable import MenuMeterCore

@Suite struct MemorySamplerTests {
    @Test func normalUsage() {
        let used = MemorySampler.calculateUsedBytes(
            active: 200_000,
            wired: 150_000,
            compressed: 100_000,
            speculative: 50_000,
            pageSize: 16_384,
            totalMemory: 17_179_869_184
        )
        #expect(used == 8_192_000_000)
    }

    @Test func clampsToTotalMemory() {
        let used = MemorySampler.calculateUsedBytes(
            active: 1_000,
            wired: 1_000,
            compressed: 0,
            speculative: 0,
            pageSize: 4_096,
            totalMemory: 1_000_000
        )
        #expect(used == 1_000_000)
    }

    @Test func zeroTotalReturnsZero() {
        let used = MemorySampler.calculateUsedBytes(
            active: 10,
            wired: 10,
            compressed: 10,
            speculative: 10,
            pageSize: 4_096,
            totalMemory: 0
        )
        #expect(used == 0)
    }

    @Test func multiplicationOverflowClampsToTotal() {
        let used = MemorySampler.calculateUsedBytes(
            active: UInt64.max,
            wired: 1,
            compressed: 0,
            speculative: 0,
            pageSize: 4_096,
            totalMemory: 1_000_000
        )
        #expect(used == 1_000_000)
    }
}
