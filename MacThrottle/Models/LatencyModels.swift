// LatencyModels.swift
// AIDEV-NOTE: Core data models for network latency monitoring

import Foundation
import SwiftUI

// MARK: - Latency Thresholds

/// Configurable thresholds for latency status levels
struct LatencyThresholds: Codable, Equatable, Sendable {
    var excellent: Double = 50   // < excellent = green
    var good: Double = 100       // < good = yellow
    var fair: Double = 200       // < fair = orange, else red

    static let `default` = LatencyThresholds()

    /// Determine status from latency in milliseconds using these thresholds
    func status(for latencyMs: Double?) -> LatencyStatus {
        guard let ms = latencyMs else { return .offline }
        switch ms {
        case ..<excellent: return .excellent
        case excellent..<good: return .good
        case good..<fair: return .fair
        default: return .poor
        }
    }
}

// MARK: - Latency Status

enum LatencyStatus: String, Codable, Sendable {
    case excellent  // < 50ms
    case good       // 50-100ms
    case fair       // 100-200ms
    case poor       // > 200ms
    case offline    // timeout/unreachable
    case unknown    // not yet measured

    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .offline: return "Offline"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .yellow
        case .fair: return .orange
        case .poor: return .red
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    var isProblematic: Bool {
        switch self {
        case .poor, .offline:
            return true
        default:
            return false
        }
    }

    /// Determine status from latency in milliseconds using default thresholds
    static func from(latencyMs: Double?) -> LatencyStatus {
        LatencyThresholds.default.status(for: latencyMs)
    }

    /// Determine status from latency using custom thresholds
    static func from(latencyMs: Double?, thresholds: LatencyThresholds) -> LatencyStatus {
        thresholds.status(for: latencyMs)
    }
}

// MARK: - Monitored Host

struct MonitoredHost: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var address: String          // IP or hostname
    var label: String            // "Gateway (en0)", "Google DNS", custom name
    var isEnabled: Bool
    var isUserDefined: Bool      // false = auto-discovered gateway
    var interfaceName: String?   // Network interface (en0, en1, etc.) - nil for user-defined hosts
    var notifyOnIssue: Bool      // Whether to send notifications for this host's issues

    // swiftlint:disable:next line_length
    init(id: UUID = UUID(), address: String, label: String, isEnabled: Bool = true, isUserDefined: Bool = false, interfaceName: String? = nil, notifyOnIssue: Bool = true) {
        self.id = id
        self.address = address
        self.label = label
        self.isEnabled = isEnabled
        self.isUserDefined = isUserDefined
        self.interfaceName = interfaceName
        self.notifyOnIssue = notifyOnIssue
    }

    static func == (lhs: MonitoredHost, rhs: MonitoredHost) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Latency Reading

struct LatencyReading: Identifiable, Sendable {
    let id: UUID
    let hostId: UUID
    let hostLabel: String
    let hostAddress: String
    let latencyMs: Double?       // nil = timeout/offline
    let status: LatencyStatus
    let timestamp: Date

    init(host: MonitoredHost, latencyMs: Double?, thresholds: LatencyThresholds = .default, timestamp: Date = Date()) {
        self.id = UUID()
        self.hostId = host.id
        self.hostLabel = host.label
        self.hostAddress = host.address
        self.latencyMs = latencyMs
        self.status = LatencyStatus.from(latencyMs: latencyMs, thresholds: thresholds)
        self.timestamp = timestamp
    }

    var displayLatency: String {
        if let ms = latencyMs {
            if ms < 1 {
                return "<1ms"
            }
            return "\(Int(ms.rounded()))ms"
        }
        return "--"
    }
}

// MARK: - History Entry

struct HistoryEntry {
    let readings: [LatencyReading]  // One per monitored host
    let timestamp: Date
    let overallStatus: LatencyStatus

    init(readings: [LatencyReading], timestamp: Date = Date()) {
        self.readings = readings
        self.timestamp = timestamp
        // Overall status = worst status among all readings
        self.overallStatus = readings.map(\.status).max(by: { $0.severity < $1.severity }) ?? .unknown
    }
}

// MARK: - Status Severity (for comparison)

private extension LatencyStatus {
    var severity: Int {
        switch self {
        case .excellent: return 0
        case .good: return 1
        case .fair: return 2
        case .poor: return 3
        case .offline: return 4
        case .unknown: return 5
        }
    }
}
