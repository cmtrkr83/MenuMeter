import Testing
@testable import MenuMeterCore

@Suite struct CPUSamplerTests {
    @Test func firstSampleReturnsZeroWithoutCrashing() {
        let current = [CPUTicks(user: 100, system: 50, nice: 0, idle: 850)]
        #expect(CPUSampler.calculateUsage(previous: nil, current: current) == 0.0)
    }

    @Test func normalDeltaCalculation() {
        let previous = [CPUTicks(user: 100, system: 50, nice: 0, idle: 850)]
        let current = [CPUTicks(user: 200, system: 100, nice: 0, idle: 900)]
        #expect(abs(CPUSampler.calculateUsage(previous: previous, current: current) - 0.75) < 0.0001)
    }

    @Test func zeroTotalReturnsZero() {
        let ticks = [CPUTicks(user: 100, system: 50, nice: 0, idle: 850)]
        #expect(CPUSampler.calculateUsage(previous: ticks, current: ticks) == 0.0)
    }

    @Test func negativeOrWrappedDeltasAreIgnored() {
        let previous = [CPUTicks(user: 100, system: 100, nice: 0, idle: 100)]
        let current = [CPUTicks(user: 50, system: 40, nice: 0, idle: 90)]
        #expect(CPUSampler.calculateUsage(previous: previous, current: current) == 0.0)
    }

    @Test func multiCoreAggregation() {
        let previous = [
            CPUTicks(user: 0, system: 0, nice: 0, idle: 0),
            CPUTicks(user: 0, system: 0, nice: 0, idle: 0),
        ]
        let current = [
            CPUTicks(user: 100, system: 0, nice: 0, idle: 100),
            CPUTicks(user: 0, system: 100, nice: 0, idle: 100),
        ]
        #expect(abs(CPUSampler.calculateUsage(previous: previous, current: current) - 0.5) < 0.0001)
    }

    @Test func coreCountMismatchUsesCommonPrefix() {
        let previous = [CPUTicks(user: 0, system: 0, nice: 0, idle: 0)]
        let current = [
            CPUTicks(user: 100, system: 0, nice: 0, idle: 100),
            CPUTicks(user: 100, system: 0, nice: 0, idle: 100),
        ]
        #expect(abs(CPUSampler.calculateUsage(previous: previous, current: current) - 0.5) < 0.0001)
    }
}
