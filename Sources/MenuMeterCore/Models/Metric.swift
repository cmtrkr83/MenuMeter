import Foundation

public enum Metric: String, CaseIterable, Sendable {
    case cpu
    case ram
    case network
    case disk
    case gpu
}
