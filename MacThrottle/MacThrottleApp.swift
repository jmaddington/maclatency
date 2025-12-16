import SwiftUI

@main
struct MacThrottleApp: App {
    @State private var monitor = ThermalMonitor()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            MenuBarIcon(pressure: monitor.pressure)
        }

        Window("About MacThrottle", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .cornerRadius(24)

            Text("MacThrottle")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Monitor your Mac's thermal pressure\nand get notified when throttling occurs.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let url = URL(string: "https://github.com/angristan/MacThrottle") {
                Link("View on GitHub", destination: url)
                    .font(.caption)
            }
        }
        .padding(32)
        .frame(width: 300)
    }
}

struct MenuBarIcon: View {
    let pressure: ThermalPressure

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(pressure.color, .primary)
    }

    private var iconName: String {
        switch pressure {
        case .nominal: return "thermometer.low"
        case .moderate: return "thermometer.medium"
        case .heavy: return "thermometer.high"
        case .trapping, .sleeping: return "thermometer.sun.fill"
        case .unknown: return "thermometer.variable.and.figure"
        }
    }
}

struct MenuContent: View {
    @Bindable var monitor: ThermalMonitor
    @State private var statusMessage: String?
    @State private var isError: Bool = false

    private var helperNeedsUpdate: Bool {
        guard monitor.daemonRunning else { return false }
        let path = "/usr/local/bin/mac-throttle-thermal-monitor"
        guard let installed = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        let installedTrimmed = installed.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedTrimmed = HelperInstaller.monitorScript.trimmingCharacters(in: .whitespacesAndNewlines)
        return installedTrimmed != expectedTrimmed
    }

    var body: some View {
        if monitor.daemonRunning {
            (Text("Thermal Pressure: ") + Text(monitor.pressure.displayName).foregroundColor(monitor.pressure.color))
                .font(.headline)

            if helperNeedsUpdate {
                Text("Helper update available")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Update Helper...") {
                    updateHelper()
                }
            }
        } else {
            Text("Helper not installed or not running")
                .font(.headline)
            Text("Required to monitor thermal pressure")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Install Helper...") {
                installHelper()
            }
        }

        if let message = statusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(isError ? .red : .green)
        }

        Divider()

        if monitor.daemonRunning {
            Menu("Notifications") {
                Toggle("On Heavy", isOn: $monitor.notifyOnHeavy)
                Toggle("On Critical", isOn: $monitor.notifyOnCritical)
                Toggle("On Recovery", isOn: $monitor.notifyOnRecovery)
                Divider()
                Toggle("Sound", isOn: $monitor.notificationSound)
            }

            Divider()

            Button("Uninstall Helper...") {
                uninstallHelper()
            }
        }

        Divider()

        Button("About MacThrottle") {
            openAboutWindow()
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @Environment(\.openWindow) private var openWindow

    private func openAboutWindow() {
        openWindow(id: "about")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installHelper() {
        runHelperInstall(update: false)
    }

    private func updateHelper() {
        runHelperInstall(update: true)
    }

    private func runHelperInstall(update: Bool) {
        statusMessage = nil
        isError = false

        let script = HelperInstaller.monitorScript
        let plist = HelperInstaller.launchDaemonPlist

        let scriptPath = "/tmp/mac-throttle-thermal-monitor.sh"
        let plistPath = "/tmp/com.macthrottle.thermal-monitor.plist"

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        } catch {
            statusMessage = "Failed to write temp files"
            isError = true
            return
        }

        let plistFile = "/Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist"
        let unloadCommand = update ? "launchctl unload \(plistFile) 2>/dev/null; " : ""

        let installCommands = """
            \(unloadCommand)cp '\(scriptPath)' /usr/local/bin/mac-throttle-thermal-monitor && \
            chmod 755 /usr/local/bin/mac-throttle-thermal-monitor && \
            cp '\(plistPath)' /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist && \
            chmod 644 /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist && \
            chown root:wheel /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist && \
            launchctl load /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist
            """

        let appleScript = """
            do shell script "\(installCommands)" with administrator privileges
            """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                statusMessage = error[NSAppleScript.errorMessage] as? String ?? "Install failed"
                isError = true
            } else {
                statusMessage = update ? "Helper updated!" : "Helper installed!"
                isError = false
            }
        }
    }

    private func uninstallHelper() {
        statusMessage = nil
        isError = false

        let uninstallCommands = """
            launchctl unload /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist 2>/dev/null; \
            rm -f /Library/LaunchDaemons/com.macthrottle.thermal-monitor.plist \
            /usr/local/bin/mac-throttle-thermal-monitor \
            /tmp/mac-throttle-thermal-state
            """

        let appleScript = """
            do shell script "\(uninstallCommands)" with administrator privileges
            """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                statusMessage = error[NSAppleScript.errorMessage] as? String ?? "Uninstall failed"
                isError = true
            } else {
                statusMessage = "Helper uninstalled"
                isError = false
            }
        }
    }
}

enum HelperInstaller {
    static let monitorScript = """
        #!/bin/bash
        OUTPUT_FILE="/tmp/mac-throttle-thermal-state"

        while true; do
            THERMAL_OUTPUT=$(powermetrics -s thermal -n 1 -i 1 2>/dev/null | grep -i "Current pressure level")

            if echo "$THERMAL_OUTPUT" | grep -qi "sleeping"; then
                PRESSURE="sleeping"
            elif echo "$THERMAL_OUTPUT" | grep -qi "trapping"; then
                PRESSURE="trapping"
            elif echo "$THERMAL_OUTPUT" | grep -qi "heavy"; then
                PRESSURE="heavy"
            elif echo "$THERMAL_OUTPUT" | grep -qi "moderate"; then
                PRESSURE="moderate"
            elif echo "$THERMAL_OUTPUT" | grep -qi "nominal"; then
                PRESSURE="nominal"
            else
                PRESSURE="unknown"
            fi

            echo "{\\"pressure\\":\\"$PRESSURE\\",\\"timestamp\\":$(date +%s)}" > "$OUTPUT_FILE"
            chmod 644 "$OUTPUT_FILE"
            sleep 10
        done
        """

    static let launchDaemonPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.macthrottle.thermal-monitor</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/mac-throttle-thermal-monitor</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
}
