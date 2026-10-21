import Testing
@testable import MenuMeterCore

@Suite struct FormatterTests {
    private func snapshot(
        cpu: Double = 0.12,
        ramUsed: UInt64 = 10_522_669_875,
        ramTotal: UInt64 = 17_179_869_184,
        down: Double = 1_258_291,
        up: Double = 419_430,
        diskUsed: UInt64 = 45_097_156_608,
        diskTotal: UInt64 = 107_374_182_400,
        gpu: Double? = 0.08
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            cpu: cpu,
            ramUsed: ramUsed,
            ramTotal: ramTotal,
            networkDown: down,
            networkUp: up,
            diskUsed: diskUsed,
            diskTotal: diskTotal,
            gpu: gpu
        )
    }

    @Test func byteFormattingThresholds() {
        #expect(ByteFormatter.bytes(0) == "0B")
        #expect(ByteFormatter.bytes(999) == "999B")
        #expect(ByteFormatter.bytes(1_024) == "1.0K")
        #expect(ByteFormatter.bytes(1_536) == "1.5K")
        #expect(ByteFormatter.bytes(1_048_576) == "1.0M")
        #expect(ByteFormatter.byteRate(1_258_291) == "1.2M")
        #expect(ByteFormatter.detailRate(419_430) == "409.6K/s")
    }

    @Test func menuBarTexts() {
        let sample = snapshot()
        #expect(StatusTextFormatter.menuBarText(for: .cpu, snapshot: sample) == "CPU 12%")
        #expect(StatusTextFormatter.menuBarText(for: .ram, snapshot: sample) == "RAM 9.8G")
        #expect(StatusTextFormatter.menuBarText(for: .network, snapshot: sample) == "Ağ ↓1.2M ↑409.6K")
        #expect(StatusTextFormatter.menuBarText(for: .disk, snapshot: sample) == "SSD 42%")
        #expect(StatusTextFormatter.menuBarText(for: .gpu, snapshot: sample) == "GPU 8%")
    }

    @Test func gpuMissingRendersDash() {
        let sample = snapshot(gpu: nil)
        #expect(StatusTextFormatter.menuBarText(for: .gpu, snapshot: sample) == "GPU —")
        #expect(StatusTextFormatter.detailLines(for: sample).last == "GPU kullanılamıyor")
    }

    @Test func detailLines() {
        let lines = StatusTextFormatter.detailLines(for: snapshot())
        #expect(lines.count == 5)
        #expect(lines[0] == "CPU 12%")
        #expect(lines[1] == "RAM 9.8 / 16.0 GB")
        #expect(lines[2] == "Ağ ↓1.2M/s ↑409.6K/s")
        #expect(lines[3] == "SSD 42% (boş 58.0 GB)")
        #expect(lines[4] == "GPU 8%")
    }

    @Test func accessibilityLabel() {
        #expect(
            StatusTextFormatter.accessibilityLabel(for: .cpu, snapshot: snapshot())
                == "CPU kullanımı yüzde 12"
        )
    }
}
