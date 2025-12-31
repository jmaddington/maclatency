// MacThrottleApp.swift
// AIDEV-NOTE: Main app entry point - network latency monitor

import SwiftUI

@main
struct MacThrottleApp: App {
    @State private var monitor = LatencyMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            MenuBarIcon(
                status: monitor.menuBarStatus,
                latency: monitor.menuBarLatency,
                displayMode: monitor.statusBarDisplayMode
            )
        }
        .menuBarExtraStyle(.window)

        Window("About MacThrottle", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
