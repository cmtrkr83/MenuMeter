import Testing
@testable import MenuMeterCore

@Suite struct NetworkSamplerTests {
    @Test func firstSampleReturnsZeroRates() {
        let current = NetworkCounters(received: 10_000, sent: 20_000)
        let rates = NetworkSampler.calculateRates(previous: nil, current: current, elapsed: 1.0)
        #expect(rates.down == 0.0)
        #expect(rates.up == 0.0)
    }

    @Test func rateCalculation() {
        let previous = NetworkCounters(received: 1_000, sent: 2_000)
        let current = NetworkCounters(received: 3_048, sent: 4_048)
        let rates = NetworkSampler.calculateRates(previous: previous, current: current, elapsed: 2.0)
        #expect(abs(rates.down - 1_024) < 0.001)
        #expect(abs(rates.up - 1_024) < 0.001)
    }

    @Test func counterResetProducesZeroRate() {
        let previous = NetworkCounters(received: 5_000, sent: 5_000)
        let current = NetworkCounters(received: 100, sent: 200)
        let rates = NetworkSampler.calculateRates(previous: previous, current: current, elapsed: 1.0)
        #expect(rates.down == 0.0)
        #expect(rates.up == 0.0)
    }

    @Test func zeroElapsedProducesZeroRate() {
        let previous = NetworkCounters(received: 0, sent: 0)
        let current = NetworkCounters(received: 100, sent: 100)
        let rates = NetworkSampler.calculateRates(previous: previous, current: current, elapsed: 0)
        #expect(rates.down == 0.0)
        #expect(rates.up == 0.0)
    }

    @Test func excludedInterfaces() {
        #expect(NetworkSampler.isIncludedInterface("en0"))
        #expect(NetworkSampler.isIncludedInterface("en1"))
        #expect(!NetworkSampler.isIncludedInterface("lo0"))
        #expect(!NetworkSampler.isIncludedInterface("utun3"))
        #expect(!NetworkSampler.isIncludedInterface("awdl0"))
        #expect(!NetworkSampler.isIncludedInterface("llw0"))
        #expect(!NetworkSampler.isIncludedInterface("bridge0"))
    }
}
