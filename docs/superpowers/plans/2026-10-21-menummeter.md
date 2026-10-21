# MenuMeter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menü çubuğunda CPU, RAM, ağ hızı, SSD doluluğu ve GPU kullanımını aynı anda yan yana gösteren, sol tıkta Activity Monitor'ü açan, minimum kaynak tüketen yerel bir AppKit uygulaması inşa etmek.

**Architecture:** SwiftPM projesi; test edilebilir ölçüm/biçimlendirme mantığı `MenuMeterCore` kütüphanesinde, AppKit arayüzü `MenuMeter` çalıştırılabilirinde. Tek `DispatchSourceTimer` üç saniyede bir tüm metrikleri örnekler; beş `NSStatusItem` halka ikonu + değeri yan yana gösterir. `scripts/build_app.sh` ad-hoc imzalı `MenuMeter.app` paketini `~/Applications/` içine kurar.

**Tech Stack:** Swift 6.4, SwiftPM, macOS Command Line Tools, AppKit (`NSStatusItem`, `NSWorkspace`), IOKit (`IOAccelerator`), Darwin (`host_processor_info`, `host_statistics64`, `sysctl`, `statfs`), ServiceManagement (`SMAppService`).

**Spec:** `docs/superpowers/specs/2026-10-21-menummeter-design.md`

> **Revizyon (2026-10-21, Task 8 sırasında):** Kullanıcı isteğiyle rotasyon kaldırıldı. Beş metrik aynı anda, beş ayrı menü çubuğu öğesinde yan yana gösterilir; her halka kısa etiketi (`CPU`, `RAM`, `AĞ`, `SSD`, `GPU`) içerir. Task 1–7'deki `MetricRotation` referansları tarihseldir; kodda ve testlerde kaldırılmıştır. Bu revizyon Task 8 ve sonrası için bağlayıcıdır.

## Global Constraints

- Yalnızca Apple yerel framework'leri kullanılacak: AppKit, Foundation, IOKit, ServiceManagement, Darwin, CoreGraphics.
- Üçüncü parti paket bağımlılığı yok.
- Full Xcode gerekmez; mevcut Command Line Tools ve Swift 6.4 ile `swift build` / `swift test` çalışmalı.
- macOS 13 ve üzeri hedeflenir.
- Ölçüm aralığı sabit 3 saniye; beş metrik her zaman birlikte, soldan sağa CPU → RAM → Ağ → SSD → GPU (rotasyon yok).
- Hedef: ortalama CPU <%0,2, fiziksel bellek footprint'i <20 MB.
- Menü çubuğu değerleri Türkçe: `12%`, `9.8G`, `↓1.2M ↑0.4M`, `42%`, `8%` / `—`; halka etiketleri `CPU`, `RAM`, `AĞ`, `SSD`, `GPU`.
- Dock simgesi yok (`LSUIElement=true` + `.accessory`).

## Review Focus

- Apple Silicon'da CPU tick sayaçları çekirdek başına 32-bit gelir; negatif/taşan delta `0` sayılmalı, oran `0...1` aralığına clamp edilmeli — Task 2 `testNegativeOrWrappedDeltasAreIgnored`.
- Ağ sayaçları VPN/loopback yüzünden çift sayılmamalı ve sayaç sıfırlanınca hız `0` olmalı — Task 4 `testExcludedInterfaces` ve `testCounterResetProducesZeroRate`.
- Apple Silicon'da `IOAccelerator` istatistiği eksik olabilir; uygulama çökmemeli, `GPU —` göstermeli — Task 5 `testMissingStatisticsReturnsNil`, Task 6 `testGPUMissingRendersDash`.
- APFS `statfs` değerlerinde sıfır/tutarsız blok sayısı `SSD —` üretmeli, sıfıra bölmemeli — Task 4 `testZeroBlocksReturnsNil`.
- Uyku/uyanma sonrası timer çoğalmamalı; `stop` sonrası `start` tek akış üretmeli — Task 7 `testRestartAfterStopDeliversSamples`.

---

### Task 1: SwiftPM İskeleti, `MetricsSnapshot`, `Metric` ve Rotasyon

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/MenuMeterCore/Models/MetricsSnapshot.swift`
- Create: `Sources/MenuMeterCore/Models/Metric.swift`
- Create: `Sources/MenuMeter/main.swift` (geçici placeholder; Task 8'de değiştirilir)
- Create: `Tests/MenuMeterCoreTests/MetricRotationTests.swift`

**Interfaces:**
- Produces:
  - `public struct MetricsSnapshot: Equatable, Sendable` — init `(cpu: Double, ramUsed: UInt64, ramTotal: UInt64, networkDown: Double, networkUp: Double, diskUsed: UInt64, diskTotal: UInt64, gpu: Double?, timestamp: Date = Date())`; computed `ramFraction: Double`, `diskFraction: Double`; `cpu` ve `gpu` init'te `0...1` aralığına clamp edilir.
  - `public enum Metric: String, CaseIterable, Sendable` — `cpu, ram, network, disk, gpu`.
  - `public struct MetricRotation` — `static let order: [Metric]`; `static func next(after: Metric) -> Metric`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class MetricRotationTests: XCTestCase {
    func testRotationOrder() {
        XCTAssertEqual(MetricRotation.order, [.cpu, .ram, .network, .disk, .gpu])
        XCTAssertEqual(MetricRotation.next(after: .cpu), .ram)
        XCTAssertEqual(MetricRotation.next(after: .ram), .network)
        XCTAssertEqual(MetricRotation.next(after: .network), .disk)
        XCTAssertEqual(MetricRotation.next(after: .disk), .gpu)
        XCTAssertEqual(MetricRotation.next(after: .gpu), .cpu)
    }

    func testSnapshotClampsCPUAndGPU() {
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
        XCTAssertEqual(snapshot.cpu, 1.0)
        XCTAssertEqual(snapshot.gpu, 0.0)
        XCTAssertEqual(snapshot.ramFraction, 0.0)
        XCTAssertEqual(snapshot.diskFraction, 0.0)
    }

    func testSnapshotFractions() {
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
        XCTAssertEqual(snapshot.ramFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.diskFraction, 0.42, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MetricRotationTests`
Expected: FAIL — `no such module 'MenuMeterCore'` veya `cannot find 'MetricsSnapshot' in scope`.

- [ ] **Step 3: Implement `Package.swift`, `.gitignore`, models and rotation**

`Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuMeter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MenuMeterCore", targets: ["MenuMeterCore"]),
        .executable(name: "MenuMeter", targets: ["MenuMeter"]),
    ],
    targets: [
        .target(
            name: "MenuMeterCore",
            linkerSettings: [.linkedFramework("IOKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MenuMeter",
            dependencies: ["MenuMeterCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MenuMeterCoreTests",
            dependencies: ["MenuMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`.gitignore`: `.build/`, `MenuMeter.app/`, `.DS_Store`.

`MetricsSnapshot.swift`: `public` struct with the exact init above. Clamp `cpu` and non-nil `gpu` with `max(0, min(1, value))`. `ramFraction` = `ramTotal > 0 ? min(1, Double(ramUsed) / Double(ramTotal)) : 0`; `diskFraction` aynı biçimde.
`Metric.swift`: enum + `MetricRotation.order` + `next(after:)` (`order[(index + 1) % count]`, bulunamazsa `.cpu`).
`Sources/MenuMeter/main.swift` (geçici): `print("MenuMeter")`. Task 8'de gerçek giriş noktasıyla değiştirilir.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MetricRotationTests`
Expected: PASS (3 test).

- [ ] **Step 5: Commit**

```bash
git init
git add Package.swift .gitignore Sources/MenuMeterCore/Models Sources/MenuMeter/main.swift Tests/MenuMeterCoreTests
git commit -m "feat: add SwiftPM skeleton, metrics snapshot and rotation"
```

---

### Task 2: `CPUSampler`

**Files:**
- Create: `Sources/MenuMeterCore/Samplers/CPUSampler.swift`
- Create: `Tests/MenuMeterCoreTests/CPUSamplerTests.swift`

**Interfaces:**
- Consumes: yok.
- Produces:
  - `public struct CPUTicks: Equatable, Sendable` — `user, system, nice, idle: UInt64`.
  - `public final class CPUSampler: @unchecked Sendable` — `init()`; `func sample() -> Double`; `static func calculateUsage(previous: [CPUTicks]?, current: [CPUTicks]) -> Double`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class CPUSamplerTests: XCTestCase {
    func testFirstSampleReturnsZeroWithoutCrashing() {
        let current = [CPUTicks(user: 100, system: 50, nice: 0, idle: 850)]
        XCTAssertEqual(CPUSampler.calculateUsage(previous: nil, current: current), 0.0)
    }

    func testNormalDeltaCalculation() {
        let previous = [CPUTicks(user: 100, system: 50, nice: 0, idle: 850)]
        let current = [CPUTicks(user: 200, system: 100, nice: 0, idle: 900)]
        XCTAssertEqual(
            CPUSampler.calculateUsage(previous: previous, current: current),
            0.75,
            accuracy: 0.0001
        )
    }

    func testZeroTotalReturnsZero() {
        let ticks = [CPUTicks(user: 100, system: 50, nice: 0, idle: 850)]
        XCTAssertEqual(CPUSampler.calculateUsage(previous: ticks, current: ticks), 0.0)
    }

    func testNegativeOrWrappedDeltasAreIgnored() {
        let previous = [CPUTicks(user: 100, system: 100, nice: 0, idle: 100)]
        let current = [CPUTicks(user: 50, system: 40, nice: 0, idle: 90)]
        XCTAssertEqual(CPUSampler.calculateUsage(previous: previous, current: current), 0.0)
    }

    func testMultiCoreAggregation() {
        let previous = [
            CPUTicks(user: 0, system: 0, nice: 0, idle: 0),
            CPUTicks(user: 0, system: 0, nice: 0, idle: 0),
        ]
        let current = [
            CPUTicks(user: 100, system: 0, nice: 0, idle: 100),
            CPUTicks(user: 0, system: 100, nice: 0, idle: 100),
        ]
        XCTAssertEqual(
            CPUSampler.calculateUsage(previous: previous, current: current),
            0.5,
            accuracy: 0.0001
        )
    }

    func testCoreCountMismatchUsesCommonPrefix() {
        let previous = [CPUTicks(user: 0, system: 0, nice: 0, idle: 0)]
        let current = [
            CPUTicks(user: 100, system: 0, nice: 0, idle: 100),
            CPUTicks(user: 100, system: 0, nice: 0, idle: 100),
        ]
        XCTAssertEqual(
            CPUSampler.calculateUsage(previous: previous, current: current),
            0.5,
            accuracy: 0.0001
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CPUSamplerTests`
Expected: FAIL — `cannot find 'CPUTicks' in scope`.

- [ ] **Step 3: Implement `CPUSampler`**

`sample()`:
1. `host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)`.
2. `info` belleğini `integer_t` dizisi olarak oku; her çekirdek için `CPU_STATE_USER`, `CPU_STATE_SYSTEM`, `CPU_STATE_NICE`, `CPU_STATE_IDLE` değerlerini negatif olmayan `UInt64`'a çevir.
3. `defer` ile `vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))` çağır.
4. İlk çağrıda tick'leri sakla ve `0` dön; sonraki çağrılarda `calculateUsage` sonucunu dön.

`calculateUsage(previous:current:)`:
- `previous == nil` ise `0`.
- Ortak çekirdek sayısı = `min(previous.count, current.count)`; bu aralıkta her alan için delta = `current >= previous ? current - previous : 0` (UInt64 underflow koruması).
- `total = Σ(userDelta + systemDelta + niceDelta + idleDelta)`; `total == 0` ise `0`.
- Sonuç `(userDelta + systemDelta + niceDelta) / total`, `0...1` clamp.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CPUSamplerTests`
Expected: PASS (6 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuMeterCore/Samplers/CPUSampler.swift Tests/MenuMeterCoreTests/CPUSamplerTests.swift
git commit -m "feat: implement CPU sampler with overflow-safe tick deltas"
```

---

### Task 3: `MemorySampler`

**Files:**
- Create: `Sources/MenuMeterCore/Samplers/MemorySampler.swift`
- Create: `Tests/MenuMeterCoreTests/MemorySamplerTests.swift`

**Interfaces:**
- Consumes: yok.
- Produces:
  - `public final class MemorySampler: @unchecked Sendable` — `init()`; `func sample() -> (used: UInt64, total: UInt64)`.
  - `static func calculateUsedBytes(active: UInt64, wired: UInt64, compressed: UInt64, speculative: UInt64, pageSize: UInt64, totalMemory: UInt64) -> UInt64`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class MemorySamplerTests: XCTestCase {
    func testNormalUsage() {
        let used = MemorySampler.calculateUsedBytes(
            active: 200_000,
            wired: 150_000,
            compressed: 100_000,
            speculative: 50_000,
            pageSize: 16_384,
            totalMemory: 17_179_869_184
        )
        XCTAssertEqual(used, 8_192_000_000)
    }

    func testClampsToTotalMemory() {
        let used = MemorySampler.calculateUsedBytes(
            active: 1_000,
            wired: 1_000,
            compressed: 0,
            speculative: 0,
            pageSize: 4_096,
            totalMemory: 1_000_000
        )
        XCTAssertEqual(used, 1_000_000)
    }

    func testZeroTotalReturnsZero() {
        let used = MemorySampler.calculateUsedBytes(
            active: 10,
            wired: 10,
            compressed: 10,
            speculative: 10,
            pageSize: 4_096,
            totalMemory: 0
        )
        XCTAssertEqual(used, 0)
    }

    func testMultiplicationOverflowClampsToTotal() {
        let used = MemorySampler.calculateUsedBytes(
            active: UInt64.max,
            wired: 1,
            compressed: 0,
            speculative: 0,
            pageSize: 4_096,
            totalMemory: 1_000_000
        )
        XCTAssertEqual(used, 1_000_000)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MemorySamplerTests`
Expected: FAIL — `cannot find 'MemorySampler' in scope`.

- [ ] **Step 3: Implement `MemorySampler`**

`sample()`:
1. `sysctlbyname("hw.memsize", &total, &size, nil, 0)`; başarısızsa `(0, 0)`.
2. `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` ile `vm_statistics64`; sayfa boyutu `vm_kernel_page_size`.
3. `calculateUsedBytes(active: wired: compressed: speculative: pageSize: totalMemory:)` sonucunu `(used, total)` dön.

`calculateUsedBytes`: toplam sayfa = dört değerin taşma korumalı toplamı; `totalMemory == 0 || pageSize == 0` ise `0`. `pageCount > totalMemory / pageSize` ise (veya çarpım taşarsa) `totalMemory`; değilse `min(totalMemory, pageCount * pageSize)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MemorySamplerTests`
Expected: PASS (4 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuMeterCore/Samplers/MemorySampler.swift Tests/MenuMeterCoreTests/MemorySamplerTests.swift
git commit -m "feat: implement memory sampler with clamp and overflow guards"
```

---

### Task 4: `DiskSampler` ve `NetworkSampler`

**Files:**
- Create: `Sources/MenuMeterCore/Samplers/DiskSampler.swift`
- Create: `Sources/MenuMeterCore/Samplers/NetworkSampler.swift`
- Create: `Tests/MenuMeterCoreTests/DiskSamplerTests.swift`
- Create: `Tests/MenuMeterCoreTests/NetworkSamplerTests.swift`

**Interfaces:**
- Consumes: yok.
- Produces:
  - `public final class DiskSampler` — `init()`; `func sample() -> (used: UInt64, total: UInt64)?`; `static func calculateUsage(blockCount: UInt64, freeBlocks: UInt64, blockSize: UInt64) -> (used: UInt64, total: UInt64)?`.
  - `public struct NetworkCounters: Equatable, Sendable` — `received, sent: UInt64`.
  - `public final class NetworkSampler: @unchecked Sendable` — `init()`; `func sample() -> (down: Double, up: Double)`; `static func calculateRates(previous: NetworkCounters?, current: NetworkCounters, elapsed: TimeInterval) -> (down: Double, up: Double)`; `static func delta(previous: UInt64, current: UInt64) -> UInt64`; `static func isIncludedInterface(_ name: String) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class DiskSamplerTests: XCTestCase {
    func testUsageCalculation() {
        let usage = DiskSampler.calculateUsage(blockCount: 1_000, freeBlocks: 400, blockSize: 4_096)
        XCTAssertEqual(usage?.used, 2_457_600)
        XCTAssertEqual(usage?.total, 4_096_000)
    }

    func testZeroBlocksReturnsNil() {
        XCTAssertNil(DiskSampler.calculateUsage(blockCount: 0, freeBlocks: 0, blockSize: 4_096))
    }

    func testFreeGreaterThanBlocksClampsUsedToZero() {
        let usage = DiskSampler.calculateUsage(blockCount: 100, freeBlocks: 150, blockSize: 4_096)
        XCTAssertEqual(usage?.used, 0)
        XCTAssertEqual(usage?.total, 409_600)
    }

    func testBlockSizeOverflowReturnsNil() {
        XCTAssertNil(DiskSampler.calculateUsage(blockCount: UInt64.max, freeBlocks: 0, blockSize: 4_096))
    }
}
```

```swift
import XCTest
@testable import MenuMeterCore

final class NetworkSamplerTests: XCTestCase {
    func testFirstSampleReturnsZeroRates() {
        let current = NetworkCounters(received: 10_000, sent: 20_000)
        let rates = NetworkSampler.calculateRates(previous: nil, current: current, elapsed: 1.0)
        XCTAssertEqual(rates.down, 0.0)
        XCTAssertEqual(rates.up, 0.0)
    }

    func testRateCalculation() {
        let previous = NetworkCounters(received: 1_000, sent: 2_000)
        let current = NetworkCounters(received: 3_048, sent: 4_048)
        let rates = NetworkSampler.calculateRates(previous: previous, current: current, elapsed: 2.0)
        XCTAssertEqual(rates.down, 1_024, accuracy: 0.001)
        XCTAssertEqual(rates.up, 1_024, accuracy: 0.001)
    }

    func testCounterResetProducesZeroRate() {
        let previous = NetworkCounters(received: 5_000, sent: 5_000)
        let current = NetworkCounters(received: 100, sent: 200)
        let rates = NetworkSampler.calculateRates(previous: previous, current: current, elapsed: 1.0)
        XCTAssertEqual(rates.down, 0.0)
        XCTAssertEqual(rates.up, 0.0)
    }

    func testZeroElapsedProducesZeroRate() {
        let previous = NetworkCounters(received: 0, sent: 0)
        let current = NetworkCounters(received: 100, sent: 100)
        let rates = NetworkSampler.calculateRates(previous: previous, current: current, elapsed: 0)
        XCTAssertEqual(rates.down, 0.0)
        XCTAssertEqual(rates.up, 0.0)
    }

    func testExcludedInterfaces() {
        XCTAssertTrue(NetworkSampler.isIncludedInterface("en0"))
        XCTAssertTrue(NetworkSampler.isIncludedInterface("en1"))
        XCTAssertFalse(NetworkSampler.isIncludedInterface("lo0"))
        XCTAssertFalse(NetworkSampler.isIncludedInterface("utun3"))
        XCTAssertFalse(NetworkSampler.isIncludedInterface("awdl0"))
        XCTAssertFalse(NetworkSampler.isIncludedInterface("llw0"))
        XCTAssertFalse(NetworkSampler.isIncludedInterface("bridge0"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "(DiskSamplerTests|NetworkSamplerTests)"`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement `DiskSampler` and `NetworkSampler`**

`DiskSampler.sample()`: `statfs("/", &stats)`; başarısızsa `nil`. `blockCount = UInt64(stats.f_blocks)`, `freeBlocks = UInt64(stats.f_bfree)`, `blockSize = UInt64(stats.f_bsize)` ile `calculateUsage` dön.
`calculateUsage`: `blockCount == 0 || blockSize == 0` ise `nil`. `total` çarpımı `multipliedReportingOverflow` ile taşarsa `nil`. `usedBlocks = blockCount > freeBlocks ? blockCount - freeBlocks : 0`; `used = usedBlocks * blockSize` (taşma varsa `nil`).

`NetworkSampler.sample()`:
1. MIB `[CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]` ile önce boyut al, sonra tamponu `sysctl` ile doldur.
2. Tamponda `if_msghdr` kayıtlarını gez; `ifm_type == RTM_IFINFO2` olanlarda `if_data64` alanından `ifi_ibytes` / `ifi_obytes` oku.
3. `if_indextoname(ifm_index, ...)` ile adı çöz; `isIncludedInterface` false ise atla.
4. Sayaçları topla; `ProcessInfo.processInfo.systemUptime` farkıyla `calculateRates` dön; ilk çağrıda `(0, 0)`.

`isIncludedInterface`: `lo0` ve `utun`, `awdl`, `llw`, `bridge` önekleri hariç tüm adlar dahil.
`delta`: `current >= previous ? current - previous : 0`.
`calculateRates`: `previous == nil || elapsed <= 0` ise `(0, 0)`; aksi halde `Double(delta) / elapsed`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "(DiskSamplerTests|NetworkSamplerTests)"`
Expected: PASS (9 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuMeterCore/Samplers/DiskSampler.swift Sources/MenuMeterCore/Samplers/NetworkSampler.swift Tests/MenuMeterCoreTests/DiskSamplerTests.swift Tests/MenuMeterCoreTests/NetworkSamplerTests.swift
git commit -m "feat: implement disk and network samplers with reset guards"
```

---

### Task 5: `GPUSampler`

**Files:**
- Create: `Sources/MenuMeterCore/Samplers/GPUSampler.swift`
- Create: `Tests/MenuMeterCoreTests/GPUSamplerTests.swift`

**Interfaces:**
- Consumes: yok.
- Produces:
  - `public final class GPUSampler: @unchecked Sendable` — `init()`; `func sample() -> Double?`; `static func parseUtilization(properties: [String: Any]) -> Double?`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class GPUSamplerTests: XCTestCase {
    func testDeviceUtilization() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 42]]
        XCTAssertEqual(GPUSampler.parseUtilization(properties: properties), 0.42, accuracy: 0.0001)
    }

    func testRendererUtilizationFallback() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Renderer Utilization %": 28]]
        XCTAssertEqual(GPUSampler.parseUtilization(properties: properties), 0.28, accuracy: 0.0001)
    }

    func testGPUCoreUtilizationFallback() {
        let properties: [String: Any] = ["PerformanceStatistics": ["GPU Core Utilization": 8]]
        XCTAssertEqual(GPUSampler.parseUtilization(properties: properties), 0.08, accuracy: 0.0001)
    }

    func testFractionalValueIsNotDividedTwice() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 0.42]]
        XCTAssertEqual(GPUSampler.parseUtilization(properties: properties), 0.42, accuracy: 0.0001)
    }

    func testValuesAboveHundredClampToOne() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": 150]]
        XCTAssertEqual(GPUSampler.parseUtilization(properties: properties), 1.0)
    }

    func testMissingStatisticsReturnsNil() {
        XCTAssertNil(GPUSampler.parseUtilization(properties: [:]))
        XCTAssertNil(GPUSampler.parseUtilization(properties: ["PerformanceStatistics": [:]]))
    }

    func testNonNumericValueReturnsNil() {
        let properties: [String: Any] = ["PerformanceStatistics": ["Device Utilization %": "high"]]
        XCTAssertNil(GPUSampler.parseUtilization(properties: properties))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GPUSamplerTests`
Expected: FAIL — `cannot find 'GPUSampler' in scope`.

- [ ] **Step 3: Implement `GPUSampler`**

`sample()`: `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))`; 0 ise `nil` (yalnızca ilk başarısızlıkta bir kez `NSLog`). Servisi `init` sırasında bir kez aç ve sakla; `deinit` içinde `IOObjectRelease`. `IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)` sonucunu `[String: Any]` olarak `parseUtilization`'a ver; property yoksa `nil`.

`parseUtilization`:
- `properties["PerformanceStatistics"] as? [String: Any]` yoksa `nil`.
- Sırayla `"Device Utilization %"`, `"Renderer Utilization %"`, `"GPU Core Utilization"` anahtarlarını ara.
- Değeri `NSNumber` üzerinden `Double`'a çevir; çevrilemezse `nil`.
- `value <= 1.0` ise olduğu gibi, değilse `value / 100`; sonucu `0...1` clamp et.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GPUSamplerTests`
Expected: PASS (7 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuMeterCore/Samplers/GPUSampler.swift Tests/MenuMeterCoreTests/GPUSamplerTests.swift
git commit -m "feat: implement GPU sampler with IOKit fallbacks"
```

---

### Task 6: Biçimlendiriciler (`ByteFormatter`, `StatusTextFormatter`)

**Files:**
- Create: `Sources/MenuMeterCore/Formatting/ByteFormatter.swift`
- Create: `Sources/MenuMeterCore/Formatting/StatusTextFormatter.swift`
- Create: `Tests/MenuMeterCoreTests/FormatterTests.swift`

**Interfaces:**
- Consumes: `Metric`, `MetricsSnapshot`.
- Produces:
  - `public enum ByteFormatter` — `static func bytes(_ value: UInt64) -> String` (`"9.8G"`); `static func byteRate(_ bytesPerSecond: Double) -> String` (`"1.2M"`); `static func detailRate(_ bytesPerSecond: Double) -> String` (`"1.2M/s"`).
  - `public enum StatusTextFormatter` — `static func menuBarText(for metric: Metric, snapshot: MetricsSnapshot) -> String`; `static func detailLines(for snapshot: MetricsSnapshot) -> [String]`; `static func accessibilityLabel(for metric: Metric, snapshot: MetricsSnapshot) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class FormatterTests: XCTestCase {
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

    func testByteFormattingThresholds() {
        XCTAssertEqual(ByteFormatter.bytes(0), "0B")
        XCTAssertEqual(ByteFormatter.bytes(999), "999B")
        XCTAssertEqual(ByteFormatter.bytes(1_024), "1.0K")
        XCTAssertEqual(ByteFormatter.bytes(1_536), "1.5K")
        XCTAssertEqual(ByteFormatter.bytes(1_048_576), "1.0M")
        XCTAssertEqual(ByteFormatter.byteRate(1_258_291), "1.2M")
        XCTAssertEqual(ByteFormatter.detailRate(419_430), "409.6K/s")
    }

    func testMenuBarTexts() {
        let sample = snapshot()
        XCTAssertEqual(StatusTextFormatter.menuBarText(for: .cpu, snapshot: sample), "CPU 12%")
        XCTAssertEqual(StatusTextFormatter.menuBarText(for: .ram, snapshot: sample), "RAM 9.8G")
        XCTAssertEqual(
            StatusTextFormatter.menuBarText(for: .network, snapshot: sample),
            "Ağ ↓1.2M ↑409.6K"
        )
        XCTAssertEqual(StatusTextFormatter.menuBarText(for: .disk, snapshot: sample), "SSD 42%")
        XCTAssertEqual(StatusTextFormatter.menuBarText(for: .gpu, snapshot: sample), "GPU 8%")
    }

    func testGPUMissingRendersDash() {
        let sample = snapshot(gpu: nil)
        XCTAssertEqual(StatusTextFormatter.menuBarText(for: .gpu, snapshot: sample), "GPU —")
        XCTAssertTrue(StatusTextFormatter.detailLines(for: sample).last == "GPU kullanılamıyor")
    }

    func testDetailLines() {
        let lines = StatusTextFormatter.detailLines(for: snapshot())
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0], "CPU 12%")
        XCTAssertEqual(lines[1], "RAM 9.8 / 16.0 GB")
        XCTAssertEqual(lines[2], "Ağ ↓1.2M/s ↑409.6K/s")
        XCTAssertEqual(lines[3], "SSD 42% (boş 58.0 GB)")
        XCTAssertEqual(lines[4], "GPU 8%")
    }

    func testAccessibilityLabel() {
        XCTAssertEqual(
            StatusTextFormatter.accessibilityLabel(for: .cpu, snapshot: snapshot()),
            "CPU kullanımı yüzde 12"
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FormatterTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement the formatters**

`ByteFormatter`:
- `bytes`: `value < 1024` ise `"\(value)B"`; aksi halde 1024 tabanıyla en büyük uygun birim (`K`, `M`, `G`, `T`) ve tek ondalıklı `String(format: "%.1f", scaled) + unit`.
- `byteRate`: aynı mantık ama ondalık `Double` girdi; negatif/sonsuz değerlerde `"0B"`.
- `detailRate`: `byteRate(...) + "/s"`.

`StatusTextFormatter`:
- `menuBarText`:
  - `.cpu`: `"CPU \(percent(snapshot.cpu))%"`
  - `.ram`: `"RAM \(ByteFormatter.bytes(snapshot.ramUsed))"`
  - `.network`: `"Ağ ↓\(ByteFormatter.byteRate(snapshot.networkDown)) ↑\(ByteFormatter.byteRate(snapshot.networkUp))"`
  - `.disk`: `"SSD \(percent(snapshot.diskFraction))%"`
  - `.gpu`: `snapshot.gpu.map { "GPU \(percent($0))%" } ?? "GPU —"`
- `percent`: `Int((value * 100).rounded())`.
- `detailLines`:
  - CPU yüzde
  - `"RAM \(gb(ramUsed)) / \(gb(ramTotal)) GB"`
  - `"Ağ ↓\(detailRate(down)) ↑\(detailRate(up))"` (indirme önce)
  - `"SSD \(percent(diskFraction))% (boş \(gb(diskTotal - diskUsed)) GB)"` (`used > total` ise boş `0`)
  - `"GPU \(percent)%"` veya `"GPU kullanılamıyor"`
- `gb`: `Double(bytes) / 1_073_741_824`, `String(format: "%.1f", ...)`.
- `accessibilityLabel`: CPU/RAM/SSD/GPU için Türkçe okunabilir metin; ağ için `"Ağ indirme X, yükleme Y"`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FormatterTests`
Expected: PASS (5 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuMeterCore/Formatting Tests/MenuMeterCoreTests/FormatterTests.swift
git commit -m "feat: add byte and status text formatters"
```

---

### Task 7: `MetricsEngine`

**Files:**
- Create: `Sources/MenuMeterCore/Services/MetricsEngine.swift`
- Create: `Tests/MenuMeterCoreTests/MetricsEngineTests.swift`

**Interfaces:**
- Consumes: tüm sampler'lar, `MetricsSnapshot`.
- Produces:
  - `public final class MetricsEngine: @unchecked Sendable` — `init(interval: TimeInterval = 3.0, cpuSampler: CPUSampler = CPUSampler(), memorySampler: MemorySampler = MemorySampler(), networkSampler: NetworkSampler = NetworkSampler(), diskSampler: DiskSampler = DiskSampler(), gpuSampler: GPUSampler = GPUSampler(), queue: DispatchQueue = DispatchQueue(label: "com.cem.MenuMeter.sampler", qos: .utility))`
  - `func start(onUpdate: @escaping @Sendable (MetricsSnapshot) -> Void)`
  - `func stop()`
  - `func sampleNow()`
  - `static func makeSnapshot(cpu: Double, memory: (used: UInt64, total: UInt64), network: (down: Double, up: Double), disk: (used: UInt64, total: UInt64)?, gpu: Double?, timestamp: Date = Date()) -> MetricsSnapshot`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MenuMeterCore

final class LockedCounter: @unchecked Sendable {
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

final class MetricsEngineTests: XCTestCase {
    func testStartDeliversImmediateSample() {
        let engine = MetricsEngine(interval: 0.05)
        let expectation = expectation(description: "sample")
        engine.start { snapshot in
            XCTAssertGreaterThanOrEqual(snapshot.cpu, 0.0)
            expectation.fulfill()
            engine.stop()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testRepeatedSamplesArrive() {
        let engine = MetricsEngine(interval: 0.05)
        let counter = LockedCounter()
        let expectation = expectation(description: "samples")
        expectation.expectedFulfillmentCount = 3
        engine.start { _ in
            counter.increment()
            expectation.fulfill()
            if counter.count == 3 { engine.stop() }
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testStopStopsDelivery() {
        let engine = MetricsEngine(interval: 0.05)
        let counter = LockedCounter()
        let first = expectation(description: "first")
        engine.start { _ in
            counter.increment()
            first.fulfill()
        }
        wait(for: [first], timeout: 2.0)
        engine.stop()
        let countAfterStop = counter.count
        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertEqual(counter.count, countAfterStop)
    }

    func testRestartAfterStopDeliversSamples() {
        let engine = MetricsEngine(interval: 0.05)
        let first = expectation(description: "first run")
        engine.start { _ in first.fulfill() }
        wait(for: [first], timeout: 2.0)
        engine.stop()

        let second = expectation(description: "second run")
        engine.start { _ in second.fulfill() }
        wait(for: [second], timeout: 2.0)
        engine.stop()
    }

    func testMakeSnapshotAssemblesValues() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let snapshot = MetricsEngine.makeSnapshot(
            cpu: 0.25,
            memory: (used: 50, total: 100),
            network: (down: 1_024, up: 2_048),
            disk: (used: 25, total: 100),
            gpu: nil,
            timestamp: timestamp
        )
        XCTAssertEqual(snapshot.cpu, 0.25)
        XCTAssertEqual(snapshot.ramFraction, 0.5)
        XCTAssertEqual(snapshot.diskFraction, 0.25)
        XCTAssertNil(snapshot.gpu)
        XCTAssertEqual(snapshot.timestamp, timestamp)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MetricsEngineTests`
Expected: FAIL — `cannot find 'MetricsEngine' in scope`.

- [ ] **Step 3: Implement `MetricsEngine`**

- `init` verilen sampler'ları ve `max(0.05, interval)` değerini saklar.
- `start(onUpdate:)`: daha önce çalışan timer varsa iptal eder (idempotent). `DispatchSource.makeTimerSource(queue: queue)` oluştur; `schedule(deadline: .now(), repeating: interval)`; handler içinde `[weak self]` ile `sampleOnce(onUpdate)` çağır. Callback `DispatchQueue.main.async` ile iletilir.
- `sampleOnce`: CPU, RAM, ağ, disk, GPU'yu sırayla örnekler; `makeSnapshot` üretir; ana kuyruğa gönderir.
- `stop()`: timer'ı `cancel()`, `timer = nil`, callback'i temizle.
- `sampleNow()`: timer yoksa hiçbir şey yapmaz; varsa hemen bir örnek üretir.
- `makeSnapshot`: verilenleri `MetricsSnapshot`'a yerleştirir; disk `nil` ise `(0, 0)` kullanır.
- `deinit`: `stop()`.
- Timer handler'ında güçlü `self` yakalamaktan kaçın; `DispatchSourceTimer` ve callback `@Sendable` uyumlu olsun.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MetricsEngineTests`
Expected: PASS (5 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuMeterCore/Services/MetricsEngine.swift Tests/MenuMeterCoreTests/MetricsEngineTests.swift
git commit -m "feat: add 3-second metrics engine with restart support"
```

---

### Task 8: AppKit Arayüzü (`NSStatusItem`, ikon, menü, Activity Monitor)

**Files:**
- Create: `Sources/MenuMeter/AppDelegate.swift`
- Create: `Sources/MenuMeter/StatusIconRenderer.swift`
- Create: `Sources/MenuMeter/StatusItemController.swift`
- Create: `Sources/MenuMeter/LoginItemController.swift`
- Create: `Sources/MenuMeter/MenuBuilder.swift`
- Modify: `Sources/MenuMeter/main.swift`

**Interfaces:**
- Consumes: `MetricsEngine`, `Metric`, `MetricsSnapshot`, `StatusTextFormatter`.
- Produces:
  - `StatusIconRenderer.icon(for: Metric, snapshot: MetricsSnapshot, size: NSSize = .init(width: 22, height: 22)) -> NSImage`
  - `StatusItemController.update(snapshot: MetricsSnapshot)`; `var onOpenActivityMonitor: (() -> Void)?`; `var onMenuNeeded: (() -> NSMenu?)?`
  - `LoginItemController.isEnabled: Bool`; `setEnabled(_:) throws`
  - `MenuBuilder.makeMenu(snapshot: MetricsSnapshot?, loginEnabled: Bool, target: AnyObject, openSelector: Selector, toggleLoginSelector: Selector, quitSelector: Selector) -> NSMenu`

- [ ] **Step 1: Implement the AppKit layer**

`main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`StatusIconRenderer`:
- `NSImage(size:flipped:drawingHandler:)` ile 22×22 template görsel üret.
- Tüm metrikler: arka plan halkası (`NSColor.black.withAlphaComponent(0.25)`) ve `NSBezierPath` yayı (`NSColor.black`); dolgu = ilgili snapshot alanı (`cpu`, `ramFraction`, `diskFraction`, `gpu ?? 0`), ağda 0. Halkanın ortasına 6 pt `shortLabel`.
- Çizgisel kalınlık 1,5 pt; `image.isTemplate = true`.

`StatusItemController`:
- `Metric.allCases` için beş `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
- Her `button`: `.imageLeading`, `monospacedDigitSystemFont(ofSize: 11)`, `target/action`, `sendAction(on: [.leftMouseUp, .rightMouseUp])`.
- Sol tık: `onOpenActivityMonitor?()`; sağ tık: tıklanan öğeye `onMenuNeeded?()` menüsünü ata, `performClick(nil)`, sonra `menu = nil`.
- `update(snapshot:)`: her öğe için ikonu yenile; değer değiştiyse `title` ve `accessibilityLabel` güncelle.

`LoginItemController`:
- `isEnabled`: `SMAppService.mainApp.status == .enabled`.
- `setEnabled`: `.register()` veya `.unregister()`; hata fırlatır.

`MenuBuilder`:
- Pasif satırlar: `StatusTextFormatter.detailLines(for:)` (`isEnabled = false`).
- Ayırıcı.
- `Etkinlik Monitörü'nü Aç` → `openSelector`.
- `Başlangıçta Aç` → `toggleLoginSelector`, `state = loginEnabled ? .on : .off`.
- Ayırıcı.
- `Çıkış` → `quitSelector`, `keyEquivalent = "q"`, `keyEquivalentModifierMask = .command`.

`AppDelegate`:
- `applicationDidFinishLaunching`: `statusController` ve `loginItemController` oluştur; closure'ları bağla; `engine.start` ile her snapshot'ta `statusController.update(snapshot:)` çağır (rotasyon yok).
- `openActivityMonitor`: `/System/Applications/Utilities/Activity Monitor.app`; `NSWorkspace.shared.openApplication(at:configuration:)` (`activates = true`); tamamlanmada hata varsa `/Applications/Utilities/Activity Monitor.app` dene; o da yoksa `NSLog`.
- `toggleLoginItem`: mevcut durumu tersine çevir; hata olursa `NSAlert` ile tek seferlik uyarı.
- `quit`: `NSApp.terminate(nil)`.
- `makeMenu`: `MenuBuilder` ile güncel snapshot ve login durumu.
- Uyku gözlemcileri: `NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification ...)` ve `screensDidSleepNotification` → `engine.stop()`; `didWakeNotification`, `screensDidWakeNotification` → `engine.start(...)`.
- `NSApp.mainMenu` için minimal uygulama menüsü: `MenuMeter` → `Çıkış` (⌘Q); pencere yok.

- [ ] **Step 2: Build the executable**

Run: `swift build`
Expected: BUILD SUCCESSFUL. CLT ortamında `ld: warning: search path ... not found` görülebilir; bunlar ortam gürültüsüdür, kod uyarısı değildir.

- [ ] **Step 3: Launch and verify manually**

Run: `swift run MenuMeter &`
Verify:
- Menü çubuğunda beş halka ve değerleri yan yana görünür (Dock'ta simge yok).
- Değerler 3 saniyede bir güncellenir; metrikler dönmez, hepsi aynı anda kalır.
- Sol tık Activity Monitor'ü öne getirir.
- Sağ tık menüsünde beş ayrıntı satırı, Activity Monitor, Başlangıçta Aç ve Çıkış bulunur.
- `kill %1` ile kapatılır.

- [ ] **Step 4: Commit**

```bash
git add Sources/MenuMeter
git commit -m "feat: add menu bar UI, status icon and Activity Monitor integration"
```

---

### Task 9: Paketleme, README ve Uçtan Uca Doğrulama

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/build_app.sh`
- Create: `README.md`
- Modify: yok

**Interfaces:**
- Produces: `~/Applications/MenuMeter.app`, ad-hoc imzalı ve çalıştırılabilir.

- [ ] **Step 1: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.cem.MenuMeter</string>
    <key>CFBundleName</key>
    <string>MenuMeter</string>
    <key>CFBundleDisplayName</key>
    <string>MenuMeter</string>
    <key>CFBundleExecutable</key>
    <string>MenuMeter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `scripts/build_app.sh`**

Script şunları yapar:
1. `set -euo pipefail`; proje kökünü `cd "$(dirname "$0")/.."` ile bulur.
2. `swift build -c release`.
3. `rm -rf ~/Applications/MenuMeter.app`; `mkdir -p ~/Applications/MenuMeter.app/Contents/{MacOS,Resources}`.
4. `.build/release/MenuMeter` binary'sini `Contents/MacOS/MenuMeter` olarak kopyalar; `Resources/Info.plist`'i `Contents/Info.plist` olarak kopyalar.
5. `codesign --force --deep --sign - ~/Applications/MenuMeter.app`.
6. `echo "Kuruldu: ~/Applications/MenuMeter.app"`.

- [ ] **Step 3: Create `README.md`**

Türkçe kısa README:
- Ne yapar (beş metrik aynı anda yan yana, 3 sn güncelleme, sol tık Activity Monitor, sağ tık menü).
- Derleme/kurulum: `./scripts/build_app.sh`.
- Çalıştırma: `open ~/Applications/MenuMeter.app`.
- Başlangıçta açma: sağ tık → Başlangıçta Aç.
- Kaldırma: önce Başlangıçta Aç'ı kapat, uygulamadan çık, `rm -rf ~/Applications/MenuMeter.app`.
- Kaynak hedefi: <%0,2 CPU, <20 MB fiziksel bellek footprint'i.

- [ ] **Step 4: Build, install and verify**

Run:
```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
codesign -vvv ~/Applications/MenuMeter.app
open ~/Applications/MenuMeter.app
sleep 3
pgrep -fl MenuMeter
```

Expected:
- `codesign` "valid on disk" ve "satisfies its Designated Requirement".
- `pgrep` iki satır değil, tek `MenuMeter` süreci.
- Menü çubuğunda beş halka ve değerleri yan yana.

Resource check:
```bash
PID="$(pgrep -x MenuMeter)"
vmmap -summary "$PID" | grep "Physical footprint"
ps -o pid,%cpu,rss,command -p "$PID"
```
Expected: `%CPU` < 1.0 (boşta), fiziksel bellek footprint'i < 20 MB. `RSS` paylaşılan framework'ler yüzünden daha yüksek görünebilir; ölçüt footprint'tir.

Manual checks:
1. Sağ tık menüsü ve ayrıntı değerleri doğru.
2. Sol tık Activity Monitor'ü açıyor.
3. `yes > /dev/null &` sonrası CPU değeri yükseliyor; `killall yes` sonrası düşüyor.
4. Uyku/uyanma sonrası metin güncellenmeye devam ediyor.
5. `killall MenuMeter` sonrası yeniden `open` çalışıyor.

- [ ] **Step 5: Commit**

```bash
git add Resources/Info.plist scripts/build_app.sh README.md
git commit -m "feat: add app bundle build script, Info.plist and README"
```

---

## Uygulama Notları

- Testler `swift test` ile tek seferde çalıştırılabilir; UI katmanı birim testi yerine derleme + manuel doğrulama ile kontrol edilir.
- Her commit öncesi `swift test` çalıştırılmalı.
- Ad-hoc imza ve `~/Applications` kurulumu, `SMAppService` başlangıç kaydı için yeterlidir; kayıt başarısız olursa menü işareti geri alınır.
- GPU istatistiği desteklenmiyorsa `GPU —` beklenen davranıştır; hata değildir.
