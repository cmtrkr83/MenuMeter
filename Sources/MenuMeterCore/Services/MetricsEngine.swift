import Foundation

public final class MetricsEngine: @unchecked Sendable {
    private let interval: TimeInterval
    private let cpuSampler: CPUSampler
    private let memorySampler: MemorySampler
    private let networkSampler: NetworkSampler
    private let diskSampler: DiskSampler
    private let gpuSampler: GPUSampler
    private let queue: DispatchQueue

    private var timer: DispatchSourceTimer?
    private var callback: (@Sendable (MetricsSnapshot) -> Void)?

    public init(
        interval: TimeInterval = 3.0,
        cpuSampler: CPUSampler = CPUSampler(),
        memorySampler: MemorySampler = MemorySampler(),
        networkSampler: NetworkSampler = NetworkSampler(),
        diskSampler: DiskSampler = DiskSampler(),
        gpuSampler: GPUSampler = GPUSampler(),
        queue: DispatchQueue = DispatchQueue(
            label: "com.cem.MenuMeter.sampler",
            qos: .utility
        )
    ) {
        self.interval = max(0.05, interval)
        self.cpuSampler = cpuSampler
        self.memorySampler = memorySampler
        self.networkSampler = networkSampler
        self.diskSampler = diskSampler
        self.gpuSampler = gpuSampler
        self.queue = queue
    }

    deinit {
        stop()
    }

    public func start(onUpdate: @escaping @Sendable (MetricsSnapshot) -> Void) {
        stop()
        callback = onUpdate

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, let callback = self.callback else { return }
            self.tick(callback: callback)
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        callback = nil
    }

    public func sampleNow() {
        guard timer != nil else { return }
        queue.async { [weak self] in
            guard let self, let callback = self.callback else { return }
            self.tick(callback: callback)
        }
    }

    private func tick(callback: @escaping @Sendable (MetricsSnapshot) -> Void) {
        let memory = memorySampler.sample()
        let network = networkSampler.sample()
        let disk = diskSampler.sample()
        let snapshot = Self.makeSnapshot(
            cpu: cpuSampler.sample(),
            memory: memory,
            network: network,
            disk: disk,
            gpu: gpuSampler.sample()
        )
        DispatchQueue.main.async {
            callback(snapshot)
        }
    }

    public static func makeSnapshot(
        cpu: Double,
        memory: (used: UInt64, total: UInt64),
        network: (down: Double, up: Double),
        disk: (used: UInt64, total: UInt64)?,
        gpu: Double?,
        timestamp: Date = Date()
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            cpu: cpu,
            ramUsed: memory.used,
            ramTotal: memory.total,
            networkDown: network.down,
            networkUp: network.up,
            diskUsed: disk?.used ?? 0,
            diskTotal: disk?.total ?? 0,
            gpu: gpu,
            timestamp: timestamp
        )
    }
}
