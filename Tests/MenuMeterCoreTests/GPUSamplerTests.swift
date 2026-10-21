import Testing
@testable import MenuMeterCore

@Suite struct GPUSamplerTests {
    @Test func deviceUtilization() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 42]]
        #expect(abs((GPUSampler.parseUtilization(properties: properties) ?? -1) - 0.42) < 0.0001)
    }

    @Test func rendererUtilizationFallback() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Renderer Utilization %": 28]]
        #expect(abs((GPUSampler.parseUtilization(properties: properties) ?? -1) - 0.28) < 0.0001)
    }

    @Test func gpuCoreUtilizationFallback() {
        let properties: [String: Any] = ["PerformanceStatistics": ["GPU Core Utilization": 8]]
        #expect(abs((GPUSampler.parseUtilization(properties: properties) ?? -1) - 0.08) < 0.0001)
    }

    @Test func fractionalValueIsNotDividedTwice() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 0.42]]
        #expect(abs((GPUSampler.parseUtilization(properties: properties) ?? -1) - 0.42) < 0.0001)
    }

    @Test func valuesAboveHundredClampToOne() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 150]]
        #expect(GPUSampler.parseUtilization(properties: properties) == 1.0)
    }

    @Test func missingStatisticsReturnsNil() {
        #expect(GPUSampler.parseUtilization(properties: [:]) == nil)
        #expect(GPUSampler.parseUtilization(properties: ["PerformanceStatistics": [:]]) == nil)
    }

    @Test func nonNumericValueReturnsNil() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": "high"]]
        #expect(GPUSampler.parseUtilization(properties: properties) == nil)
    }
}
