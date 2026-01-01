// MenuBarIcon.swift
// AIDEV-NOTE: Menu bar icon for network latency status

import SwiftUI

struct MenuBarIcon: View {
    let status: LatencyStatus
    let latency: Double?
    let displayMode: StatusBarDisplayMode
    let thresholds: LatencyThresholds

    var body: some View {
        HStack(spacing: 6) {
            if displayMode != .textOnly {
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColor, .primary)
            }
            if displayMode.showsText, let ms = latency {
                Text(formatLatency(ms))
                    .monospacedDigit()
            }
        }
    }

    /// Icon color - gradient interpolation or discrete status color
    private var iconColor: Color {
        if displayMode == .iconGradient, let ms = latency {
            return gradientColor(for: ms)
        }
        return status.color
    }

    /// Calculate gradient color based on latency relative to thresholds
    /// AIDEV-NOTE: Smooth color transition between green/yellow/orange/red [GRADIENT-CALC]
    private func gradientColor(for ms: Double) -> Color {
        let t = thresholds.validated

        // Below excellent: pure green
        if ms < t.excellent {
            return .green
        }

        // Excellent to Good: green → yellow
        if ms < t.good {
            let progress = (ms - t.excellent) / (t.good - t.excellent)
            return interpolateColor(from: .green, to: .yellow, progress: progress)
        }

        // Good to Fair: yellow → orange
        if ms < t.fair {
            let progress = (ms - t.good) / (t.fair - t.good)
            return interpolateColor(from: .yellow, to: .orange, progress: progress)
        }

        // Above fair: orange → red (cap at 2x fair threshold)
        let maxMs = t.fair * 2
        if ms < maxMs {
            let progress = (ms - t.fair) / (maxMs - t.fair)
            return interpolateColor(from: .orange, to: .red, progress: progress)
        }

        // Very high latency: pure red
        return .red
    }

    /// Linear interpolation between two colors
    private func interpolateColor(from: Color, to: Color, progress: Double) -> Color {
        let p = min(max(progress, 0), 1)  // Clamp to 0-1

        // Convert to RGB components
        let fromComponents = NSColor(from).usingColorSpace(.sRGB) ?? NSColor.green
        let toComponents = NSColor(to).usingColorSpace(.sRGB) ?? NSColor.red

        let r = fromComponents.redComponent + (toComponents.redComponent - fromComponents.redComponent) * p
        let g = fromComponents.greenComponent + (toComponents.greenComponent - fromComponents.greenComponent) * p
        let b = fromComponents.blueComponent + (toComponents.blueComponent - fromComponents.blueComponent) * p

        return Color(red: r, green: g, blue: b)
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
