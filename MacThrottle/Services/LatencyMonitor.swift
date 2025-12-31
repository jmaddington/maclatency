// LatencyMonitor.swift
// AIDEV-NOTE: Main orchestrator for network latency monitoring - replaces ThermalMonitor

import Foundation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class LatencyMonitor {
    // MARK: - Constants

    private static let historyDurationSeconds: TimeInterval = 600  // 10 minutes
    private static let pingTimeoutSeconds: TimeInterval = 2.0

    // MARK: - Configurable Poll Interval

    static let pollIntervalOptions: [Double] = [1, 2, 3, 5, 10]

    var pollIntervalSeconds: Double = UserDefaults.standard.object(forKey: "pollIntervalSeconds") as? Double ?? 3.0 {
        didSet {
            UserDefaults.standard.set(pollIntervalSeconds, forKey: "pollIntervalSeconds")
            restartTimer()
        }
    }

    // MARK: - Observable State

    private(set) var hosts: [MonitoredHost] = []
    private(set) var latestReadings: [UUID: LatencyReading] = [:]  // keyed by host ID
    private(set) var history: [HistoryEntry] = []
    private(set) var overallStatus: LatencyStatus = .unknown
    private(set) var worstLatency: Double?

    private var timer: Timer?
    private var previousOverallStatus: LatencyStatus = .unknown
    private var previousHostStatuses: [UUID: LatencyStatus] = [:]  // Per-host status tracking
    private var hostProblematicSince: [UUID: Date] = [:]  // When each host first became problematic
    private var pendingNotifications: [UUID: LatencyStatus] = [:]  // Notifications waiting for delay
    private var isMonitoring = false

    // MARK: - Threshold Editing State

    /// When true, UI is editing thresholds and we should use a frozen snapshot for evaluations
    var isEditingThresholds: Bool = false

    /// Snapshot of thresholds to use while editing is active
    var frozenThresholds: LatencyThresholds? = nil

    // MARK: - User Settings (persisted to UserDefaults)

    // swiftlint:disable:next line_length
    var userDefinedHosts: [MonitoredHost] = (try? JSONDecoder().decode([MonitoredHost].self, from: UserDefaults.standard.data(forKey: "userDefinedHosts") ?? Data())) ?? [] {
        didSet { persistUserHosts() }
    }

    var notifyOnPoor: Bool = UserDefaults.standard.object(forKey: "notifyOnPoor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnPoor, forKey: "notifyOnPoor") }
    }

    var notifyOnOffline: Bool = UserDefaults.standard.object(forKey: "notifyOnOffline") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnOffline, forKey: "notifyOnOffline") }
    }

    var notifyOnRecovery: Bool = UserDefaults.standard.object(forKey: "notifyOnRecovery") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notifyOnRecovery, forKey: "notifyOnRecovery") }
    }

    var notificationSound: Bool = UserDefaults.standard.object(forKey: "notificationSound") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notificationSound, forKey: "notificationSound") }
    }

    var showLatencyInMenuBar: Bool = UserDefaults.standard.object(forKey: "showLatencyInMenuBar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showLatencyInMenuBar, forKey: "showLatencyInMenuBar") }
    }

    // MARK: - Status Bar Display Settings

    /// What to show in status bar: icon only, text only, or both
    var statusBarDisplayMode: StatusBarDisplayMode = {
        guard let rawValue = UserDefaults.standard.string(forKey: "statusBarDisplayMode"),
              let mode = StatusBarDisplayMode(rawValue: rawValue) else {
            return .iconAndText
        }
        return mode
    }() {
        didSet { UserDefaults.standard.set(statusBarDisplayMode.rawValue, forKey: "statusBarDisplayMode") }
    }

    /// What text to show: latest ping or moving average
    var textDisplayMode: TextDisplayMode = {
        guard let rawValue = UserDefaults.standard.string(forKey: "textDisplayMode"),
              let mode = TextDisplayMode(rawValue: rawValue) else {
            return .latestPing
        }
        return mode
    }() {
        didSet { UserDefaults.standard.set(textDisplayMode.rawValue, forKey: "textDisplayMode") }
    }

    /// Window size for moving average calculation in seconds
    static let movingAverageOptions: [Double] = [5, 10, 15, 30, 60]

    var movingAverageSeconds: Double = UserDefaults.standard.object(forKey: "movingAverageSeconds") as? Double ?? 10.0 {
        didSet { UserDefaults.standard.set(movingAverageSeconds, forKey: "movingAverageSeconds") }
    }

    /// Whether to auto-discover and ping network gateways
    var autoDiscoverGateways: Bool = UserDefaults.standard.object(forKey: "autoDiscoverGateways") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoDiscoverGateways, forKey: "autoDiscoverGateways")
            refreshHosts()
        }
    }

    /// Delay in seconds before sending notification (0 = immediate)
    static let notificationDelayOptions: [Double] = [0, 5, 10, 15, 30, 60]

    var notificationDelaySeconds: Double = UserDefaults.standard.object(forKey: "notificationDelaySeconds") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(notificationDelaySeconds, forKey: "notificationDelaySeconds") }
    }

    // swiftlint:disable:next line_length
    var thresholds: LatencyThresholds = (try? JSONDecoder().decode(LatencyThresholds.self, from: UserDefaults.standard.data(forKey: "thresholds") ?? Data())) ?? .default {
        didSet { persistThresholds() }
    }

    private func persistThresholds() {
        if let data = try? JSONEncoder().encode(thresholds) {
            UserDefaults.standard.set(data, forKey: "thresholds")
        }
    }

    // MARK: - Icon Source Selection

    /// The host ID to use for menu bar icon color. If nil, use worst latency (default behavior)
    var iconSourceHostId: UUID? = {
        guard let uuidString = UserDefaults.standard.string(forKey: "iconSourceHostId") else { return nil }
        return UUID(uuidString: uuidString)
    }() {
        didSet {
            if let id = iconSourceHostId {
                UserDefaults.standard.set(id.uuidString, forKey: "iconSourceHostId")
            } else {
                UserDefaults.standard.removeObject(forKey: "iconSourceHostId")
            }
        }
    }

    /// Latency for menu bar icon (specific host or worst)
    var iconLatency: Double? {
        if let hostId = iconSourceHostId, let reading = latestReadings[hostId] {
            return reading.latencyMs
        }
        return worstLatency
    }

    /// Status for menu bar icon (specific host or overall)
    var iconStatus: LatencyStatus {
        // Prefer a specific host if selected
        if let hostId = iconSourceHostId, let reading = latestReadings[hostId] {
            // Re-evaluate using effective thresholds while editing
            let effective = isEditingThresholds ? frozenThresholds : nil
            if let ms = reading.latencyMs {
                return LatencyStatus.from(latencyMs: ms, thresholds: thresholds, effective: effective)
            } else {
                return .offline
            }
        }
        // Fallback to overall status; if editing, recompute worst among latestReadings
        if isEditingThresholds {
            let effective = frozenThresholds
            let statuses = latestReadings.values.map { r -> LatencyStatus in
                if let ms = r.latencyMs {
                    return LatencyStatus.from(latencyMs: ms, thresholds: thresholds, effective: effective)
                } else {
                    return .offline
                }
            }
            return statuses.max(by: { $0.severity < $1.severity }) ?? .unknown
        }
        return overallStatus
    }

    /// Calculate moving average latency over the configured window
    /// AIDEV-NOTE: Uses history entries within movingAverageSeconds window [MAVG-CALC]
    var movingAverageLatency: Double? {
        let cutoff = Date().addingTimeInterval(-movingAverageSeconds)
        let recentEntries = history.filter { $0.timestamp >= cutoff }
        guard !recentEntries.isEmpty else { return iconLatency }

        // If a specific host is selected, average that host's readings
        if let hostId = iconSourceHostId {
            let latencies = recentEntries.compactMap { entry in
                entry.readings.first(where: { $0.hostId == hostId })?.latencyMs
            }
            guard !latencies.isEmpty else { return nil }
            return latencies.reduce(0, +) / Double(latencies.count)
        }

        // Otherwise, average the worst latency from each entry
        let worstLatencies = recentEntries.compactMap { entry -> Double? in
            entry.readings.compactMap(\.latencyMs).max()
        }
        guard !worstLatencies.isEmpty else { return nil }
        return worstLatencies.reduce(0, +) / Double(worstLatencies.count)
    }

    /// Latency to display in menu bar (based on textDisplayMode)
    var displayLatency: Double? {
        switch textDisplayMode {
        case .latestPing:
            return iconLatency
        case .movingAverage:
            return movingAverageLatency
        }
    }

    // MARK: - Computed Properties

    var timeInEachState: [(status: LatencyStatus, duration: TimeInterval)] {
        guard history.count >= 2 else { return [] }

        var durations: [LatencyStatus: TimeInterval] = [:]

        for i in 0..<(history.count - 1) {
            let current = history[i]
            let next = history[i + 1]
            let duration = next.timestamp.timeIntervalSince(current.timestamp)
            durations[current.overallStatus, default: 0] += duration
        }

        // Add time for the current (last) state up to now
        if let last = history.last {
            let duration = Date().timeIntervalSince(last.timestamp)
            durations[last.overallStatus, default: 0] += duration
        }

        // Sort by duration descending
        return durations.map { (status: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
    }

    var totalHistoryDuration: TimeInterval {
        guard let first = history.first else { return 0 }
        return Date().timeIntervalSince(first.timestamp)
    }

    /// Get readings sorted by host label
    var sortedReadings: [LatencyReading] {
        Array(latestReadings.values).sorted { $0.hostLabel < $1.hostLabel }
    }

    // MARK: - Initialization

    init() {
        requestNotificationPermission()
        refreshHosts()
        startMonitoring()
    }

    @MainActor
    deinit {
        timer?.invalidate()
    }

    // MARK: - Host Management

    /// Refresh the list of monitored hosts (gateways + user-defined)
    func refreshHosts() {
        var newHosts: [MonitoredHost] = []

        // Discover gateways (if enabled)
        if autoDiscoverGateways {
            let gatewayHosts = GatewayDiscovery.shared.discoverGatewayHosts(forceRefresh: true)
            newHosts.append(contentsOf: gatewayHosts)
        }

        // Add user-defined hosts
        newHosts.append(contentsOf: userDefinedHosts)

        // If no hosts found, add default DNS servers
        if newHosts.isEmpty {
            newHosts = defaultHosts()
        }

        hosts = newHosts
    }

    /// Add a user-defined host
    func addHost(address: String, label: String) {
        let host = MonitoredHost(
            address: address,
            label: label.isEmpty ? address : label,
            isEnabled: true,
            isUserDefined: true
        )
        userDefinedHosts.append(host)
        refreshHosts()
    }

    /// Remove a user-defined host
    func removeHost(_ host: MonitoredHost) {
        userDefinedHosts.removeAll { $0.id == host.id }
        latestReadings.removeValue(forKey: host.id)
        refreshHosts()
    }

    /// Toggle host enabled state
    func toggleHost(_ host: MonitoredHost) {
        if let index = userDefinedHosts.firstIndex(where: { $0.id == host.id }) {
            userDefinedHosts[index].isEnabled.toggle()
        }
        refreshHosts()
    }

    /// Toggle host notification setting
    func toggleHostNotification(_ host: MonitoredHost) {
        if let index = userDefinedHosts.firstIndex(where: { $0.id == host.id }) {
            userDefinedHosts[index].notifyOnIssue.toggle()
        }
    }

    private func defaultHosts() -> [MonitoredHost] {
        [
            MonitoredHost(address: "8.8.8.8", label: "Google DNS", isEnabled: true, isUserDefined: false),
            MonitoredHost(address: "1.1.1.1", label: "Cloudflare", isEnabled: true, isUserDefined: false)
        ]
    }

    private func persistUserHosts() {
        if let data = try? JSONEncoder().encode(userDefinedHosts) {
            UserDefaults.standard.set(data, forKey: "userDefinedHosts")
        }
    }

    // MARK: - Monitoring

    @MainActor
    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Initial read
        Task { [weak self] in
            await self?.updateLatencyState()
        }

        timer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateLatencyState()
            }
        }
    }

    @MainActor
    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateLatencyState()
            }
        }
    }

    @MainActor
    private func updateLatencyState() async {
        let enabledHosts = hosts.filter(\.isEnabled)
        guard !enabledHosts.isEmpty else { return }

        let readings = await NetworkLatencyReader.shared.pingMultiple(
            enabledHosts,
            timeout: Self.pingTimeoutSeconds,
            thresholds: thresholds
        )

        // Update latest readings
        for reading in readings {
            latestReadings[reading.hostId] = reading
        }

        // Calculate overall status (worst among all)
        let newOverallStatus = readings.map(\.status).max(by: { $0.severity < $1.severity }) ?? .unknown

        // Calculate worst latency
        let latencies = readings.compactMap(\.latencyMs)
        worstLatency = latencies.max()

        // Handle per-host notifications with delay tracking
        let now = Date()
        for reading in readings {
            let previousStatus = previousHostStatuses[reading.hostId] ?? .unknown

            // Track when host becomes problematic
            if reading.status.isProblematic && !previousStatus.isProblematic {
                hostProblematicSince[reading.hostId] = now
                pendingNotifications[reading.hostId] = reading.status
            }
            // Clear tracking when host recovers
            else if !reading.status.isProblematic && previousStatus.isProblematic {
                hostProblematicSince.removeValue(forKey: reading.hostId)
                pendingNotifications.removeValue(forKey: reading.hostId)
            }

            // Check if delayed notification should fire
            if let startTime = hostProblematicSince[reading.hostId],
               let pendingStatus = pendingNotifications[reading.hostId],
               now.timeIntervalSince(startTime) >= notificationDelaySeconds {
                handleHostStatusChange(
                    hostId: reading.hostId,
                    hostLabel: reading.hostLabel,
                    from: .unknown,  // Use unknown as "was not problematic"
                    to: pendingStatus
                )
                pendingNotifications.removeValue(forKey: reading.hostId)
            }

            previousHostStatuses[reading.hostId] = reading.status
        }

        // Handle overall status change (for recovery notification)
        if newOverallStatus != previousOverallStatus {
            handleOverallStatusChange(from: previousOverallStatus, to: newOverallStatus)
            previousOverallStatus = newOverallStatus
        }

        overallStatus = newOverallStatus

        // Record history
        let entry = HistoryEntry(readings: readings)
        history.append(entry)

        // Trim old entries
        let cutoff = Date().addingTimeInterval(-Self.historyDurationSeconds)
        history.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Notifications

    /// Check if a host has notifications enabled
    private func shouldNotifyForHost(_ hostId: UUID) -> Bool {
        // Check user-defined hosts
        if let host = userDefinedHosts.first(where: { $0.id == hostId }) {
            return host.notifyOnIssue
        }
        // Gateway hosts always notify (could be made configurable in future)
        return true
    }

    private func handleHostStatusChange(hostId: UUID, hostLabel: String, from previous: LatencyStatus, to current: LatencyStatus) {
        guard shouldNotifyForHost(hostId) else { return }

        // Notify on degradation to poor
        if current == .poor && notifyOnPoor && !previous.isProblematic {
            sendNotification(
                title: "High Latency: \(hostLabel)",
                body: "Latency has exceeded \(Int(thresholds.fair))ms"
            )
        }
        // Notify on going offline
        else if current == .offline && notifyOnOffline && previous != .offline {
            sendNotification(
                title: "Host Offline: \(hostLabel)",
                body: "Unable to reach \(hostLabel)"
            )
        }
    }

    private func handleOverallStatusChange(from previous: LatencyStatus, to current: LatencyStatus) {
        // Notify on recovery (when all hosts recover)
        if notifyOnRecovery && previous.isProblematic && !current.isProblematic && current != .unknown {
            sendNotification(
                title: "Network Recovered",
                body: "All hosts responding normally"
            )
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if notificationSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Status Severity Extension

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

