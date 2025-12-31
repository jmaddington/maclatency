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
    private var isMonitoring = false

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
        if let hostId = iconSourceHostId, let reading = latestReadings[hostId] {
            return reading.status
        }
        return overallStatus
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

        // Discover gateways
        let gatewayHosts = GatewayDiscovery.shared.discoverGatewayHosts(forceRefresh: true)
        newHosts.append(contentsOf: gatewayHosts)

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

        // Handle notifications
        if newOverallStatus != previousOverallStatus {
            handleStatusChange(from: previousOverallStatus, to: newOverallStatus)
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

    private func handleStatusChange(from previous: LatencyStatus, to current: LatencyStatus) {
        // Notify on degradation
        if current == .poor && notifyOnPoor && !previous.isProblematic {
            sendNotification(
                title: "High Network Latency",
                body: "Network latency has exceeded 200ms"
            )
        } else if current == .offline && notifyOnOffline && previous != .offline {
            sendNotification(
                title: "Network Offline",
                body: "Unable to reach monitored hosts"
            )
        }

        // Notify on recovery
        if notifyOnRecovery && previous.isProblematic && !current.isProblematic && current != .unknown {
            sendNotification(
                title: "Network Recovered",
                body: "Network latency has returned to normal"
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
