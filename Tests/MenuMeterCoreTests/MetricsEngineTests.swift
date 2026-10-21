import Foundation
import Testing
@testable import MenuMeterCore

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MetricsSnapshot?

    func store(_ snapshot: MetricsSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    var snapshot: MetricsSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite struct MetricsEngineTests {
    @Test func startDeliversImmediateSample() async {
        let engine = MetricsEngine(interval: 0.05)
        let box = SnapshotBox()
        engine.start { box.store($0) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        engine.stop()

        #expect(box.snapshot != nil)
        #expect((box.snapshot?.cpu ?? -1) >= 0)
    }

    @Test func repeatedSamplesArrive() async {
        let engine = MetricsEngine(interval: 0.05)
        let counter = LockedCounter()
        engine.start { _ in counter.increment() }
        try? await Task.sleep(nanoseconds: 400_000_000)
        engine.stop()

        #expect(counter.count >= 3)
    }

    @Test func stopStopsDelivery() async {
        let engine = MetricsEngine(interval: 0.05)
        let counter = LockedCounter()
        engine.start { _ in counter.increment() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        engine.stop()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let countAfterStop = counter.count
        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(counter.count == countAfterStop)
    }

    @Test func restartAfterStopDeliversSamples() async {
        let engine = MetricsEngine(interval: 0.05)
        let counter = LockedCounter()

        engine.start { _ in counter.increment() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        engine.stop()
        let countAfterFirstRun = counter.count
        #expect(countAfterFirstRun >= 1)

        engine.start { _ in counter.increment() }
        try? await Task.sleep(nanoseconds: 150_000_000)
        engine.stop()

        #expect(counter.count > countAfterFirstRun)
    }

    @Test func makeSnapshotAssemblesValues() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let snapshot = MetricsEngine.makeSnapshot(
            cpu: 0.25,
            memory: (used: 50, total: 100),
            network: (down: 1_024, up: 2_048),
            disk: (used: 25, total: 100),
            gpu: nil,
            timestamp: timestamp
        )
        #expect(snapshot.cpu == 0.25)
        #expect(snapshot.ramFraction == 0.5)
        #expect(snapshot.diskFraction == 0.25)
        #expect(snapshot.gpu == nil)
        #expect(snapshot.timestamp == timestamp)
    }
}
