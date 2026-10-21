import Darwin
import Foundation

public struct CPUTicks: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let nice: UInt64
    public let idle: UInt64

    public init(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) {
        self.user = user
        self.system = system
        self.nice = nice
        self.idle = idle
    }
}

public final class CPUSampler: @unchecked Sendable {
    private var previousTicks: [CPUTicks]?

    public init() {}

    public func sample() -> Double {
        guard let ticks = Self.readTicks(), !ticks.isEmpty else { return 0 }
        let usage = Self.calculateUsage(previous: previousTicks, current: ticks)
        previousTicks = ticks
        return usage
    }

    public static func calculateUsage(previous: [CPUTicks]?, current: [CPUTicks]) -> Double {
        guard let previous, !previous.isEmpty, !current.isEmpty else { return 0 }
        let count = min(previous.count, current.count)
        var busy: UInt64 = 0
        var total: UInt64 = 0

        for index in 0..<count {
            let old = previous[index]
            let new = current[index]
            let user = delta(old.user, new.user)
            let system = delta(old.system, new.system)
            let nice = delta(old.nice, new.nice)
            let idle = delta(old.idle, new.idle)
            busy = busy &+ user &+ system &+ nice
            total = total &+ user &+ system &+ nice &+ idle
        }

        guard total > 0 else { return 0 }
        return max(0, min(1, Double(busy) / Double(total)))
    }

    private static func delta(_ previous: UInt64, _ current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private static func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }

        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                size
            )
        }

        let cores = Int(cpuCount)
        guard cores > 0, infoCount >= mach_msg_type_number_t(cores * Int(CPU_STATE_MAX)) else {
            return nil
        }

        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(cores)

        for core in 0..<cores {
            let base = core * Int(CPU_STATE_MAX)
            func read(_ state: Int32) -> UInt64 {
                UInt64(max(0, Int64(info[base + Int(state)])))
            }
            ticks.append(
                CPUTicks(
                    user: read(CPU_STATE_USER),
                    system: read(CPU_STATE_SYSTEM),
                    nice: read(CPU_STATE_NICE),
                    idle: read(CPU_STATE_IDLE)
                )
            )
        }

        return ticks
    }
}
