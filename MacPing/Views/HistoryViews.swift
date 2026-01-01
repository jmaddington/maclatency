// HistoryViews.swift
// AIDEV-NOTE: Graph and statistics views for network latency history

import SwiftUI

private struct WidthPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HistoryGraphView: View {
    // MARK: - Constants
    private static let maxPoints = 300
    private static let minLatencyBound: Double = 0
    private static let maxLatencyBound: Double = 300
    private static let latencyPadding: Double = 10

    // MARK: - Properties
    let history: [HistoryEntry]
    let hosts: [MonitoredHost]
    @State private var hoverLocation: CGPoint?

    private var historyDuration: TimeInterval {
        guard let first = history.first else { return 0 }
        return Date().timeIntervalSince(first.timestamp)
    }

    private var downsampledHistory: [HistoryEntry] {
        guard history.count > Self.maxPoints else { return history }

        let step = Double(history.count) / Double(Self.maxPoints)
        var result: [HistoryEntry] = []
        result.reserveCapacity(Self.maxPoints)

        for i in 0..<Self.maxPoints {
            let index = min(Int(Double(i) * step), history.count - 1)
            result.append(history[index])
        }

        if let last = history.last, result.last?.timestamp != last.timestamp {
            result[result.count - 1] = last
        }

        return result
    }

    private var latencyRange: (min: Double, max: Double) {
        var allLatencies: [Double] = []
        for entry in downsampledHistory {
            for reading in entry.readings {
                if let ms = reading.latencyMs {
                    allLatencies.append(ms)
                }
            }
        }
        guard !allLatencies.isEmpty else { return (Self.minLatencyBound, 100) }
        let minLat = max(Self.minLatencyBound, (allLatencies.min() ?? 0) - Self.latencyPadding)
        let maxLat = min(Self.maxLatencyBound, (allLatencies.max() ?? 100) + Self.latencyPadding)
        return (minLat, max(maxLat, minLat + 20))  // Ensure at least 20ms range
    }

    private func yPositionForLatency(_ ms: Double, height: CGFloat) -> CGFloat {
        let range = latencyRange
        let padding: CGFloat = 4
        let normalized = (ms - range.min) / (range.max - range.min)
        // Invert: lower latency = higher on screen
        return padding + (1.0 - CGFloat(normalized)) * (height - padding * 2)
    }

    private func entryAt(x: CGFloat, width: CGFloat) -> (entry: HistoryEntry, xPosition: CGFloat)? {
        guard history.count >= 2, let first = history.first else { return nil }
        let totalDuration = Date().timeIntervalSince(first.timestamp)
        guard totalDuration > 0 else { return nil }

        let fraction = x / width
        let targetTime = first.timestamp.addingTimeInterval(totalDuration * fraction)

        guard let closest = history.min(by: {
            abs($0.timestamp.timeIntervalSince(targetTime)) < abs($1.timestamp.timeIntervalSince(targetTime))
        }) else { return nil }

        let entryX = CGFloat(closest.timestamp.timeIntervalSince(first.timestamp) / totalDuration) * width
        return (closest, entryX)
    }

    // Assign colors to hosts
    private var hostColors: [UUID: Color] {
        let colors: [Color] = [.blue, .purple, .cyan, .pink, .mint, .indigo]
        var result: [UUID: Color] = [:]
        for (index, host) in hosts.enumerated() {
            result[host.id] = colors[index % colors.count]
        }
        return result
    }

    @State private var graphWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 2) {
            graphView
                .background(GeometryReader { geo in
                    Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
                })
                .onPreferenceChange(WidthPreferenceKey.self) { graphWidth = $0 }
                .overlay(alignment: .topTrailing) {
                    tooltipView
                }

            HStack {
                Text(formatTimeAgo(historyDuration))
                Spacer()
                Text("now")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            // Legend
            if hosts.count > 1 {
                legendView
            }
        }
    }

    private var graphView: some View {
        Canvas { context, size in
            let sampled = downsampledHistory
            guard sampled.count >= 2 else { return }

            guard let firstEntry = sampled.first else { return }
            let startTime = firstEntry.timestamp
            let endTime = Date()
            let totalDuration = endTime.timeIntervalSince(startTime)

            guard totalDuration > 0 else { return }

            // Draw status background bands
            var currentStatus = sampled[0].overallStatus
            var segmentStart: CGFloat = 0

            for i in 0..<sampled.count {
                let entry = sampled[i]
                let x = CGFloat(entry.timestamp.timeIntervalSince(startTime) / totalDuration) * size.width

                if entry.overallStatus != currentStatus {
                    let rect = CGRect(x: segmentStart, y: 0, width: x - segmentStart, height: size.height)
                    context.fill(Path(rect), with: .color(currentStatus.color.opacity(0.15)))
                    currentStatus = entry.overallStatus
                    segmentStart = x
                }
            }
            // Draw final segment
            let finalRect = CGRect(x: segmentStart, y: 0, width: size.width - segmentStart, height: size.height)
            context.fill(Path(finalRect), with: .color(currentStatus.color.opacity(0.15)))

            // Draw latency lines per host
            let colors = hostColors
            for host in hosts where host.isEnabled {
                let hostColor = colors[host.id] ?? .primary

                var path = Path()
                var firstPoint = true

                for entry in sampled {
                    guard let reading = entry.readings.first(where: { $0.hostId == host.id }),
                          let ms = reading.latencyMs else { continue }

                    let x = CGFloat(entry.timestamp.timeIntervalSince(startTime) / totalDuration) * size.width
                    let y = yPositionForLatency(ms, height: size.height)

                    if firstPoint {
                        path.move(to: CGPoint(x: x, y: y))
                        firstPoint = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Extend to current time
                if let last = sampled.last,
                   let reading = last.readings.first(where: { $0.hostId == host.id }),
                   let ms = reading.latencyMs {
                    let y = yPositionForLatency(ms, height: size.height)
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                context.stroke(path, with: .color(hostColor.opacity(0.8)), lineWidth: 1.5)

                // Current value dot
                if let last = sampled.last,
                   let reading = last.readings.first(where: { $0.hostId == host.id }),
                   let ms = reading.latencyMs {
                    let y = yPositionForLatency(ms, height: size.height)
                    let circle = Path(ellipseIn: CGRect(x: size.width - 4, y: y - 4, width: 8, height: 8))
                    context.fill(circle, with: .color(hostColor))
                }
            }

            // Latency range labels
            let range = latencyRange
            let labelStyle = Font.system(size: 8)
            let labelColor = Color.secondary.opacity(0.8)
            let maxLabel = Text("\(Int(range.max))ms").font(labelStyle).foregroundColor(labelColor)
            let minLabel = Text("\(Int(range.min))ms").font(labelStyle).foregroundColor(labelColor)
            context.draw(maxLabel, at: CGPoint(x: 4, y: 4), anchor: .topLeading)
            context.draw(minLabel, at: CGPoint(x: 4, y: size.height - 4), anchor: .bottomLeading)

            // Hover indicator
            if let location = hoverLocation, let result = entryAt(x: location.x, width: size.width) {
                let hoverX = result.xPosition

                var linePath = Path()
                linePath.move(to: CGPoint(x: hoverX, y: 0))
                linePath.addLine(to: CGPoint(x: hoverX, y: size.height))
                context.stroke(linePath, with: .color(.primary.opacity(0.3)), lineWidth: 1)

                // Hover dots for each host
                for reading in result.entry.readings {
                    if let ms = reading.latencyMs {
                        let hostColor = colors[reading.hostId] ?? .primary
                        let y = yPositionForLatency(ms, height: size.height)
                        let circle = Path(ellipseIn: CGRect(x: hoverX - 4, y: y - 4, width: 8, height: 8))
                        context.fill(circle, with: .color(hostColor))
                        context.stroke(circle, with: .color(.primary), lineWidth: 1.5)
                    }
                }
            }
        }
        .frame(height: 70)
        .drawingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3), lineWidth: 1))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
            case .ended:
                hoverLocation = nil
            }
        }
    }

    @ViewBuilder
    private var tooltipView: some View {
        if let location = hoverLocation, let result = entryAt(x: location.x, width: graphWidth) {
            let entry = result.entry
            let timeAgo = Int(Date().timeIntervalSince(entry.timestamp))
            let timeStr = timeAgo < 60 ? "\(timeAgo)s ago" : "\(timeAgo / 60)m ago"

            VStack(alignment: .leading, spacing: 2) {
                Text(timeStr)
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
                ForEach(entry.readings) { reading in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hostColors[reading.hostId] ?? .gray)
                            .frame(width: 6, height: 6)
                        Text(reading.displayLatency)
                            .font(.system(size: 8, weight: .medium))
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(4)
        }
    }

    @ViewBuilder
    private var legendView: some View {
        HStack(spacing: 8) {
            ForEach(hosts.filter(\.isEnabled)) { host in
                HStack(spacing: 3) {
                    Circle()
                        .fill(hostColors[host.id] ?? .gray)
                        .frame(width: 6, height: 6)
                    Text(host.label)
                        .font(.system(size: 8))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    private func formatTimeAgo(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h ago"
            }
            return "\(hours)h \(mins)m ago"
        }
    }
}

struct TimeBreakdownView: View {
    let timeInEachState: [(status: LatencyStatus, duration: TimeInterval)]
    let totalDuration: TimeInterval

    private static let allStates: [LatencyStatus] = [.excellent, .good, .fair, .poor, .offline]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.allStates, id: \.self) { status in
                let duration = timeInEachState.first { $0.status == status }?.duration ?? 0
                HStack {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    HStack(spacing: 2) {
                        Text(status.displayName)
                        if status.isProblematic {
                            Text("(problem)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(formatDuration(duration))
                        .foregroundStyle(.secondary)
                    if totalDuration > 0 {
                        let percentage = (duration / totalDuration * 100).rounded()
                        Text("(\(Int(percentage))%)")
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
