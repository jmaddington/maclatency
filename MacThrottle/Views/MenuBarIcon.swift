// MenuBarIcon.swift
// AIDEV-NOTE: Menu bar icon for network latency status

import SwiftUI

struct MenuBarIcon: View {
    let status: LatencyStatus
    let latency: Double?
    let displayMode: StatusBarDisplayMode

    var body: some View {
        HStack(spacing: 6) {
            if displayMode != .textOnly {
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(status.color, .primary)
            }
            if displayMode != .iconOnly, let ms = latency {
                Text(formatLatency(ms))
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        switch status {
        case .excellent:
            return "wifi"
        case .good:
            return "wifi"
        case .fair:
            return "wifi.exclamationmark"
        case .poor:
            return "wifi.exclamationmark"
        case .offline:
            return "wifi.slash"
        case .unknown:
            return "wifi.circle"
        }
    }

    private func formatLatency(_ ms: Double) -> String {
        if ms < 1 {
            return "<1ms"
        }
        return "\(Int(ms.rounded()))ms"
    }
}
