import Foundation

enum PowerSettingsRunner {
    private static let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Hibernal/power.log")

    static func setKeepAwakeOnPowerAdapter(_ enabled: Bool) {
        DispatchQueue.main.async {
            let minutes = enabled ? 0 : 10
            let label = enabled ? "enable AC keep-awake" : "restore AC sleep timer"
            PrivilegedHelperManager.setACSleepTimer(minutes: minutes) { success in
                if success {
                    appendLog(label: label, command: "/usr/bin/pmset -c sleep \(minutes)", success: true)
                    return
                }
                NSLog("Hibernal: helper \(label) failed, falling back to admin prompt")
                runAdminCommand(
                    enabled ? "/usr/bin/pmset -c sleep 0" : "/usr/bin/pmset -c sleep 10",
                    label: label
                )
            }
        }
    }

    static func openTerminalWithPmsetStatus() {
        do {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Hibernal", isDirectory: true)
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

            let scriptURL = supportDir.appendingPathComponent("pmset-check.command")
            let script = """
            #!/bin/bash
            pmset -g
            echo ""
            echo "--- custom ---"
            pmset -g custom
            echo ""
            echo "--- assertions ---"
            pmset -g assertions
            echo ""
            echo "Done. You can close this window."
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Terminal", scriptURL.path]
            try process.run()
        } catch {
            NSLog("Hibernal: failed to open Terminal for pmset: \(error)")
        }
    }

    private static func appendLog(label: String, command: String, success: Bool) {
        do {
            try FileManager.default.createDirectory(
                at: logPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let status = success ? "ok" : "failed"
            let entry = "=== \(Date()) \(label) [\(status)] ===\n\(command)\n"
            if FileManager.default.fileExists(atPath: logPath.path) {
                let handle = try FileHandle(forWritingTo: logPath)
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8) ?? Data())
                try handle.close()
            } else {
                try entry.write(to: logPath, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("Hibernal: failed to write power log: \(error)")
        }
    }

    private static func runAdminCommand(_ command: String, label: String) {
        do {
            try FileManager.default.createDirectory(
                at: logPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let logged = "echo \"=== $(date) \(label) ===\"; \(command) >> '\(logPath.path)' 2>&1"
            PrivilegedHelperManager.runAdminCommand(logged, label: label) { success in
                if !success {
                    NSLog("Hibernal: \(label) admin fallback failed")
                }
            }
        } catch {
            NSLog("Hibernal: \(label) setup failed: \(error)")
        }
    }
}