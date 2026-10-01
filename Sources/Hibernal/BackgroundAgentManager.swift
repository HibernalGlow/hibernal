import AppKit
import Foundation

enum BackgroundAgentManager {
    static let settingsChangedNotification = Notification.Name("com.hibernal.settingsChanged")
    static let showSettingsNotification = Notification.Name("com.hibernal.showSettings")
    static let hideSettingsNotification = Notification.Name("com.hibernal.hideSettings")
    static let stopBackgroundServiceNotification = Notification.Name("com.hibernal.stopBackgroundService")
    static let startBackgroundServiceNotification = Notification.Name("com.hibernal.startBackgroundService")

    private static var launchAgentLabel: String { "com.hibernal.agent" }

    private static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    static func executablePath() -> String? {
        Bundle.main.executableURL?.path
    }

    static func isAppRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID
        }
    }

    static func isOtherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != myPID
        }
    }

    static func ensureRunning() {
        guard !isAppRunning() else { return }
        guard let appURL = Bundle.main.bundleURL as URL? else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
    }

    static func requestShowSettings() {
        DistributedNotificationCenter.default().post(
            name: showSettingsNotification,
            object: nil
        )
    }

    static func requestHideSettings() {
        DistributedNotificationCenter.default().post(
            name: hideSettingsNotification,
            object: nil
        )
    }

    static func isBackgroundServiceActive() -> Bool {
        SettingsStore.shared.backgroundServiceActive
    }

    static func requestStopBackgroundService() {
        SettingsStore.shared.backgroundServiceActive = false
        DistributedNotificationCenter.default().post(
            name: stopBackgroundServiceNotification,
            object: nil
        )
        notifySettingsChanged()
    }

    static func requestStartBackgroundService() {
        SettingsStore.shared.backgroundServiceActive = true
        DistributedNotificationCenter.default().post(
            name: startBackgroundServiceNotification,
            object: nil
        )
        notifySettingsChanged()
    }

    static func markTerminationAllowed() {
        SettingsStore.shared.setAllowTermination(true)
    }

    static func consumeTerminationAllowed() -> Bool {
        SettingsStore.shared.consumeAllowTermination()
    }

    static func stopApp() {
        markTerminationAllowed()
        _ = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentPlistURL.path])
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleID {
            app.terminate()
        }
    }

    static func installLaunchAgent() -> Bool {
        guard let executable = executablePath() else { return false }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executable, "--login"],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try FileManager.default.createDirectory(
                at: launchAgentPlistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: launchAgentPlistURL)
            return reloadLaunchAgent()
        } catch {
            NSLog("Hibernal: failed to install launch agent: \(error)")
            return false
        }
    }

    static func uninstallLaunchAgent() -> Bool {
        _ = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentPlistURL.path])
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
        return true
    }

    static func syncLaunchAgent(enabled: Bool) {
        if enabled {
            _ = installLaunchAgent()
        } else {
            _ = uninstallLaunchAgent()
        }
    }

    @discardableResult
    private static func reloadLaunchAgent() -> Bool {
        _ = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentPlistURL.path])
        return runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentPlistURL.path])
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func notifySettingsChanged() {
        DistributedNotificationCenter.default().post(name: settingsChangedNotification, object: nil)
    }
}