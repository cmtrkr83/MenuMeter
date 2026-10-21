import Testing
@testable import MenuMeterCore

@Suite struct MetricRotationTests {
    @Test func rotationOrder() {
        #expect(MetricRotation.order == [.cpu, .ram, .network, .disk, .gpu])
        #expect(MetricRotation.next(after: .cpu) == .ram)
        #expect(MetricRotation.next(after: .ram) == .network)
        #expect(MetricRotation.next(after: .network) == .disk)
        #expect(MetricRotation.next(after: .disk) == .gpu)
        #expect(MetricRotation.next(after: .gpu) == .cpu)
    }

    @Test func snapshotClampsCPUAndGPU() {
        let snapshot = MetricsSnapshot(
            cpu: 1.4,
            ramUsed: 0,
            ramTotal: 0,
            networkDown: 0,
            networkUp: 0,
            diskUsed: 0,
            diskTotal: 0,
            gpu: -0.2
        )
        #expect(snapshot.cpu == 1.0)
        #expect(snapshot.gpu == 0.0)
        #expect(snapshot.ramFraction == 0.0)
        #expect(snapshot.diskFraction == 0.0)
    }

    @Test func snapshotFractions() {
        let snapshot = MetricsSnapshot(
            cpu: 0.5,
            ramUsed: 8_589_934_592,
            ramTotal: 17_179_869_184,
            networkDown: 0,
            networkUp: 0,
            diskUsed: 42,
            diskTotal: 100,
            gpu: nil
        )
        #expect(abs(snapshot.ramFraction - 0.5) < 0.0001)
        #expect(abs(snapshot.diskFraction - 0.42) < 0.0001)
    }
}
