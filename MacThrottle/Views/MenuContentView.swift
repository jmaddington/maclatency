// MenuContentView.swift
// AIDEV-NOTE: Main menu content for network latency monitor

import SwiftUI

struct MenuContentView: View {
    @Bindable var monitor: LatencyMonitor
    @Environment(\.openWindow) private var openWindow
    @State private var newHostAddress: String = ""
    @State private var newHostLabel: String = ""
    @State private var showAddHost: Bool = false
    @State private var showThresholds: Bool = false

    @FocusState private var focusedThresholdField: ThresholdField?

    private enum ThresholdField: Hashable {
        case excellent, good, fair
    }

    /// Get color for latency using current thresholds
    private func colorForLatency(_ ms: Double) -> Color {
        let effective = monitor.isEditingThresholds ? monitor.frozenThresholds : nil
        return monitor.thresholds.status(for: ms, effective: effective).color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Network Status:")
                Text(monitor.overallStatus.displayName)
                    .foregroundColor(monitor.overallStatus.color)
                    .fontWeight(.semibold)
                Spacer()
                if let latency = monitor.worstLatency {
                    Text("\(Int(latency.rounded()))ms")
                        .foregroundColor(colorForLatency(latency))
                        .fontWeight(.semibold)
                        .help("Worst latency")
                }
            }
            .font(.headline)

            // Per-host latency readings
            if !monitor.sortedReadings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(monitor.sortedReadings) { reading in
                        HStack {
                            Circle()
                                .fill(reading.status.color)
                                .frame(width: 8, height: 8)
                            Text(reading.hostLabel)
                                .lineLimit(1)

                            // Icon source indicator/button
                            Button {
                                if monitor.iconSourceHostId == reading.hostId {
                                    monitor.iconSourceHostId = nil  // Toggle off
                                } else {
                                    monitor.iconSourceHostId = reading.hostId
                                }
                            } label: {
                                Image(systemName: monitor.iconSourceHostId == reading.hostId
                                    ? "target"
                                    : "circle.dotted")
                                    .foregroundColor(monitor.iconSourceHostId == reading.hostId
                                        ? .accentColor
                                        : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(monitor.iconSourceHostId == reading.hostId
                                ? "Using for icon (click to use worst)"
                                : "Use for menu bar icon")

                            Spacer()
                            Text(reading.displayLatency)
                                .foregroundColor(reading.status.color)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }

            // History graph
            if monitor.history.count >= 2 {
                HistoryGraphView(history: monitor.history, hosts: monitor.hosts)
            }

            // Statistics
            if !monitor.timeInEachState.isEmpty {
                Divider()
                Text("Statistics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimeBreakdownView(
                    timeInEachState: monitor.timeInEachState,
                    totalDuration: monitor.totalHistoryDuration
                )
            }

            Divider()

            // Hosts section
            hostsSection

            Divider()

            // Settings
            Text("Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLoginManager.shared.isEnabled },
                set: { LaunchAtLoginManager.shared.isEnabled = $0 }
            ))
            .controlSize(.small)

            // Status bar display mode
            HStack {
                Text("Menu Bar:")
                Spacer()
                Picker("", selection: $monitor.statusBarDisplayMode) {
                    ForEach(StatusBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
            }
            .controlSize(.small)

            // Text display mode (only show if text is displayed)
            if monitor.statusBarDisplayMode != .iconOnly {
                HStack {
                    Text("Show:")
                    Spacer()
                    Picker("", selection: $monitor.textDisplayMode) {
                        ForEach(TextDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 120)
                }
                .controlSize(.small)

                // Moving average window (only show if moving average selected)
                if monitor.textDisplayMode == .movingAverage {
                    HStack {
                        Text("Avg Window:")
                        Spacer()
                        Picker("", selection: $monitor.movingAverageSeconds) {
                            ForEach(LatencyMonitor.movingAverageOptions, id: \.self) { seconds in
                                Text("\(Int(seconds))s").tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 60)
                    }
                    .controlSize(.small)
                }
            }

            HStack {
                Text("Poll Interval:")
                Spacer()
                Picker("", selection: $monitor.pollIntervalSeconds) {
                    ForEach(LatencyMonitor.pollIntervalOptions, id: \.self) { interval in
                        Text("\(Int(interval))s").tag(interval)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 60)
            }
            .controlSize(.small)

            // Thresholds section
            thresholdsSection

            Divider()

            Text("Notifications")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                Toggle("On Poor (>\(Int((monitor.isEditingThresholds ? (monitor.frozenThresholds?.fair ?? monitor.thresholds.fair) : monitor.thresholds.fair)))ms)", isOn: $monitor.notifyOnPoor)
                Toggle("On Offline", isOn: $monitor.notifyOnOffline)
                Toggle("On Recovery", isOn: $monitor.notifyOnRecovery)
                Toggle("Sound", isOn: $monitor.notificationSound)

                HStack {
                    Text("Delay:")
                    Spacer()
                    Picker("", selection: $monitor.notificationDelaySeconds) {
                        ForEach(LatencyMonitor.notificationDelayOptions, id: \.self) { delay in
                            if delay == 0 {
                                Text("Immediate").tag(delay)
                            } else {
                                Text("\(Int(delay))s").tag(delay)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
            .controlSize(.small)

            Divider()

            HStack {
                Button("About") {
                    openAboutWindow()
                }
                .controlSize(.small)

                Spacer()

                Button("Refresh") {
                    monitor.refreshHosts()
                }
                .controlSize(.small)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    @ViewBuilder
    private var hostsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Monitored Hosts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddHost.toggle()
                } label: {
                    Image(systemName: showAddHost ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.plain)
                .help(showAddHost ? "Cancel" : "Add host")
            }

            Toggle("Auto-discover Gateways", isOn: $monitor.autoDiscoverGateways)
                .controlSize(.small)

            if showAddHost {
                addHostForm
            }

            // List user-defined hosts with delete option
            ForEach(monitor.userDefinedHosts) { host in
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(host.label)
                        .lineLimit(1)
                    Text("(\(host.address))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()

                    // Notification toggle
                    Button {
                        monitor.toggleHostNotification(host)
                    } label: {
                        Image(systemName: host.notifyOnIssue ? "bell.fill" : "bell.slash")
                            .foregroundStyle(host.notifyOnIssue ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(host.notifyOnIssue ? "Notifications enabled" : "Notifications disabled")

                    Button {
                        monitor.removeHost(host)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove host")
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var addHostForm: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("IP or hostname", text: $newHostAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            HStack {
                TextField("Label (optional)", text: $newHostLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Add") {
                    if !newHostAddress.isEmpty {
                        monitor.addHost(address: newHostAddress, label: newHostLabel)
                        newHostAddress = ""
                        newHostLabel = ""
                        showAddHost = false
                    }
                }
                .controlSize(.small)
                .disabled(newHostAddress.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showThresholds.toggle()
            } label: {
                HStack {
                    Text("Thresholds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: showThresholds ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showThresholds {
                VStack(alignment: .leading, spacing: 4) {
                    thresholdRow(label: "Excellent (<", value: $monitor.thresholds.excellent, color: .green)
                    thresholdRow(label: "Good (<", value: $monitor.thresholds.good, color: .yellow)
                    thresholdRow(label: "Fair (<", value: $monitor.thresholds.fair, color: .orange)
                    Text("Poor (≥\(Int(monitor.thresholds.fair))ms)")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(.leading, 8)
            }
        }
    }

    @ViewBuilder
    private func thresholdRow(label: String, value: Binding<Double>, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(color)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .font(.caption2)
                .focused($focusedThresholdField, equals: fieldForBinding(value))
                .onChange(of: focusedThresholdField) { _, newFocus in
                    let isEditing = newFocus != nil
                    if isEditing && !monitor.isEditingThresholds {
                        monitor.isEditingThresholds = true
                        monitor.frozenThresholds = monitor.thresholds
                    } else if !isEditing && monitor.isEditingThresholds {
                        monitor.isEditingThresholds = false
                        monitor.frozenThresholds = nil
                    }
                }
            Text("ms)")
                .font(.caption2)
                .foregroundColor(color)
        }
    }

    private func fieldForBinding(_ binding: Binding<Double>) -> ThresholdField? {
        if binding.wrappedValue == monitor.thresholds.excellent { return .excellent }
        if binding.wrappedValue == monitor.thresholds.good { return .good }
        if binding.wrappedValue == monitor.thresholds.fair { return .fair }
        return nil
    }

    private func openAboutWindow() {
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
    }
}

