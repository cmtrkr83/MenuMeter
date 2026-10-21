import Foundation
import IOKit

public final class GPUSampler: @unchecked Sendable {
    private let service: io_service_t

    public init() {
        service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator")
        )
        if service == 0 {
            NSLog("MenuMeter: GPU istatistikleri kullanılamıyor")
        }
    }

    deinit {
        if service != 0 {
            IOObjectRelease(service)
        }
    }

    public func sample() -> Double? {
        guard service != 0 else { return nil }
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        guard let statistics = property.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return Self.parseUtilization(properties: ["PerformanceStatistics": statistics])
    }

    public static func parseUtilization(properties: [String: Any]) -> Double? {
        guard let statistics = properties["PerformanceStatistics"] as? [String: Any] else {
            return nil
        }

        let keys = [
            "Device Utilization %",
            "Renderer Utilization %",
            "GPU Core Utilization",
        ]

        for key in keys {
            guard let number = statistics[key] as? NSNumber else { continue }
            let value = number.doubleValue
            let normalized = value <= 1.0 ? value : value / 100.0
            return max(0, min(1, normalized))
        }

        return nil
    }
}
