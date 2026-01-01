// GatewayDiscovery.swift
// AIDEV-NOTE: Discovers active network gateways from routing table

import Foundation

/// Gateway information including address and interface
struct GatewayInfo: Hashable {
    let address: String
    let interface: String  // e.g., "en0", "en1"
}

/// Discovers active network gateways on the system
final class GatewayDiscovery {
    nonisolated(unsafe) static let shared = GatewayDiscovery()

    private var cachedGateways: [GatewayInfo] = []
    private var lastDiscoveryTime: Date?
    private let cacheValiditySeconds: TimeInterval = 30  // Re-discover every 30s

    private init() {}

    /// Discover all active gateways, using cache if recent
    func discoverGateways(forceRefresh: Bool = false) -> [GatewayInfo] {
        if !forceRefresh,
           let lastTime = lastDiscoveryTime,
           Date().timeIntervalSince(lastTime) < cacheValiditySeconds,
           !cachedGateways.isEmpty {
            return cachedGateways
        }

        let gateways = fetchGateways()
        cachedGateways = gateways
        lastDiscoveryTime = Date()
        return gateways
    }

    /// Create MonitoredHost objects for discovered gateways
    func discoverGatewayHosts(forceRefresh: Bool = false) -> [MonitoredHost] {
        let gateways = discoverGateways(forceRefresh: forceRefresh)
        return gateways.map { info in
            MonitoredHost(
                address: info.address,
                label: "Gateway (\(info.interface))",
                isEnabled: true,
                isUserDefined: false,
                interfaceName: info.interface
            )
        }
    }

    /// Fetch gateways from routing table using netstat
    private func fetchGateways() -> [GatewayInfo] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-rn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseGateways(from: output)
    }

    /// Parse netstat -rn output to find default gateways
    /// Example lines:
    /// default            192.168.1.1        UGScg          en0
    /// default            fe80::1%en0        UGcIg          en0
    private func parseGateways(from output: String) -> [GatewayInfo] {
        var gateways: Set<GatewayInfo> = []

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let components = line.split(separator: " ", omittingEmptySubsequences: true)

            // Looking for lines that start with "default" with at least 4 columns
            // Columns: destination, gateway, flags, netif
            guard components.count >= 4,
                  components[0] == "default" else {
                continue
            }

            let gateway = String(components[1])
            let interface = String(components[3])

            // Filter out localhost and link-local addresses
            if isValidGateway(gateway) {
                gateways.insert(GatewayInfo(address: gateway, interface: interface))
            }
        }

        // Sort by interface name for consistent ordering
        return gateways.sorted { $0.interface < $1.interface }
    }

    /// Check if a gateway address is valid (not localhost, not link-local)
    private func isValidGateway(_ address: String) -> Bool {
        // Skip localhost
        if address.hasPrefix("127.") || address == "::1" {
            return false
        }

        // Skip link-local IPv6 (fe80::)
        if address.lowercased().hasPrefix("fe80::") {
            return false
        }

        // Skip "link#" entries (macOS uses these for directly connected networks)
        if address.hasPrefix("link#") {
            return false
        }

        // Basic validation: should have at least one dot (IPv4) or colon (IPv6)
        if !address.contains(".") && !address.contains(":") {
            return false
        }

        return true
    }

    /// Clear the cache to force re-discovery
    func clearCache() {
        cachedGateways = []
        lastDiscoveryTime = nil
    }
}
