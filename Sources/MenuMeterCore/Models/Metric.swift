import Foundation

public enum Metric: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case ram
    case disk
    case network
}
