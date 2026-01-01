// MacPingApp.swift
// AIDEV-NOTE: Main app entry point - network latency monitor

import SwiftUI

@main
struct MacPingApp: App {
    @State private var monitor = LatencyMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            MenuBarIcon(
                status: monitor.menuBarStatus,
                latency: monitor.menuBarLatency,
                displayMode: monitor.statusBarDisplayMode,
                thresholds: monitor.thresholds
            )
        }
        .menuBarExtraStyle(.window)

        Window("About MacPing", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
