// NetworkLatencyReader.swift
// AIDEV-NOTE: Ping implementation using /sbin/ping - sandbox compatible

import Foundation

/// Reads network latency by executing ping commands
final class NetworkLatencyReader: Sendable {
    static let shared = NetworkLatencyReader()

    private init() {}

    /// Ping a host and return the round-trip time in milliseconds
    /// Returns nil if the host is unreachable or times out
    func ping(_ host: String, timeout: TimeInterval = 2.0) async -> Double? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.syncPing(host, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchronous ping implementation
    private func syncPing(_ host: String, timeout: TimeInterval) -> Double? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c 1: send one packet
        // -W: timeout in milliseconds (macOS ping uses ms)
        let timeoutMs = Int(timeout * 1000)
        process.arguments = ["-c", "1", "-W", "\(timeoutMs)", host]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseLatency(from: output)
    }

    /// Parse the ping output to extract round-trip time
    /// Example output: "64 bytes from 8.8.8.8: icmp_seq=0 ttl=117 time=12.345 ms"
    private func parseLatency(from output: String) -> Double? {
        // Look for "time=X.XXX ms" pattern
        let pattern = #"time[=<](\d+\.?\d*)\s*ms"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range) else {
            return nil
        }

        guard let timeRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let timeString = String(output[timeRange])
        return Double(timeString)
    }

    /// Ping multiple hosts concurrently and return results
    func pingMultiple(
        _ hosts: [MonitoredHost],
        timeout: TimeInterval = 2.0,
        thresholds: LatencyThresholds = .default
    ) async -> [LatencyReading] {
        // Capture thresholds for Sendable compliance
        let capturedThresholds = thresholds

        return await withTaskGroup(of: LatencyReading.self) { group in
            for host in hosts where host.isEnabled {
                // Capture values explicitly to satisfy Swift 6 Sendable requirements
                let capturedHost = host
                let capturedTimeout = timeout
                group.addTask {
                    let latency = await self.ping(capturedHost.address, timeout: capturedTimeout)
                    return LatencyReading(host: capturedHost, latencyMs: latency, thresholds: capturedThresholds)
                }
            }

            var results: [LatencyReading] = []
            for await reading in group {
                results.append(reading)
            }
            return results
        }
    }
}
