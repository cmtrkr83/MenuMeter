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

    @Test func menuBarValues() {
        let sample = snapshot()
        #expect(StatusTextFormatter.shortLabel(for: .cpu) == "CPU")
        #expect(StatusTextFormatter.shortLabel(for: .ram) == "RAM")
        #expect(StatusTextFormatter.shortLabel(for: .network) == "AĞ")
        #expect(StatusTextFormatter.shortLabel(for: .disk) == "SSD")
        #expect(StatusTextFormatter.shortLabel(for: .gpu) == "GPU")

        #expect(StatusTextFormatter.menuBarValue(for: .cpu, snapshot: sample) == "12%")
        #expect(StatusTextFormatter.menuBarValue(for: .ram, snapshot: sample) == "9.8G")
        #expect(
            StatusTextFormatter.menuBarValue(for: .network, snapshot: sample)
                == "↓1.2M ↑409.6K"
        )
        #expect(StatusTextFormatter.menuBarValue(for: .disk, snapshot: sample) == "42%")
        #expect(StatusTextFormatter.menuBarValue(for: .gpu, snapshot: sample) == "8%")
    }

    @Test func gpuMissingRendersDash() {
        let sample = snapshot(gpu: nil)
        #expect(StatusTextFormatter.menuBarValue(for: .gpu, snapshot: sample) == "—")
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
