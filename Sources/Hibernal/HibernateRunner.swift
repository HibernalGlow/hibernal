import Foundation

enum HibernateRunner {
    private static let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Hibernal/hibernate.log")

    private static var generation = 0
    private static var scriptRunning = false

    static func trigger(restoreAfterWake: Bool, ejectDrives: Bool) {
        DispatchQueue.main.async {
            generation += 1
            let currentGeneration = generation
            NSLog("Hibernal: hibernate requested (generation \(currentGeneration))")

            HibernateProgressController.shared.begin(generation: currentGeneration) {
                guard currentGeneration == generation else {
                    NSLog("Hibernal: hibernate cancelled (generation \(currentGeneration) superseded)")
                    return
                }
                guard !scriptRunning else {
                    NSLog("Hibernal: hibernate skipped (script already running)")
                    return
                }
                runHibernate(
                    generation: currentGeneration,
                    restoreAfterWake: restoreAfterWake,
                    ejectDrives: ejectDrives
                )
            }
        }
    }

    static func cancelPending() {
        generation += 1
        NSLog("Hibernal: pending hibernate cancelled")
    }

    private static func runHibernate(
        generation: Int,
        restoreAfterWake: Bool,
        ejectDrives: Bool
    ) {
        scriptRunning = true
        do {
            let supportDir = try supportDirectory()
            let scriptPath = try writeScript(
                in: supportDir,
                restoreAfterWake: restoreAfterWake,
                ejectDrives: ejectDrives
            )
            PrivilegedHelperManager.executeHibernateScript(at: scriptPath.path) { success in
                scriptRunning = false
                guard generation == self.generation else { return }
                if success { return }
                NSLog("Hibernal: helper hibernate failed, falling back to admin prompt")
                runViaAdmin(scriptPath: scriptPath)
            }
        } catch {
            scriptRunning = false
            NSLog("Hibernal: failed to prepare hibernate script: \(error)")
        }
    }

    private static func supportDirectory() throws -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hibernal", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir
    }

    private static func writeScript(
        in supportDir: URL,
        restoreAfterWake: Bool,
        ejectDrives: Bool
    ) throws -> URL {
        let scriptURL = supportDir.appendingPathComponent("hibernate.sh")
        let logPath = logPath.path
        let lockDir = supportDir.appendingPathComponent("hibernate.lock", isDirectory: true).path

        let ejectBlock = ejectDrives ? """
        echo "=== $(date) ejecting external drives ===" >> "$LOG"
        while IFS= read -r disk; do
            [[ -z "$disk" ]] && continue
            /usr/sbin/diskutil eject "$disk" >> "$LOG" 2>&1 || true
        done < <(/usr/sbin/diskutil list external physical 2>/dev/null | awk '/^\\/dev\\/disk[0-9]+/ {print $1}')
        """ : ""

        let restoreBlock = restoreAfterWake ? """
        echo "=== $(date) wake restore ===" >> "$LOG"
        pmset -a hibernatemode 3 >> "$LOG" 2>&1
        pmset -b hibernatemode 3 >> "$LOG" 2>&1
        pmset -c hibernatemode 3 >> "$LOG" 2>&1
        pmset -a standby 1 >> "$LOG" 2>&1
        pmset -a autopoweroff 1 >> "$LOG" 2>&1
        pmset -a powernap 1 >> "$LOG" 2>&1
        pmset -a womp 1 >> "$LOG" 2>&1
        pkill -SIGCONT grok-macos-aarch64 2>/dev/null || true
        launchctl kickstart -k system/com.apple.AirPlayXPCHelper 2>/dev/null || true
        killall Finder 2>/dev/null || true
        """ : """
        pkill -SIGCONT grok-macos-aarch64 2>/dev/null || true
        """

        let script = """
        #!/bin/bash
        set -euo pipefail
        LOG="\(logPath)"
        LOCK_DIR="\(lockDir)"
        SCRIPT_PATH="\(scriptURL.path)"
        mkdir -p "$(dirname "$LOG")"

        if [[ -d "$LOCK_DIR" ]] && ! pgrep -f "$SCRIPT_PATH" >/dev/null 2>&1; then
            rmdir "$LOCK_DIR" 2>/dev/null || true
        fi

        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            echo "=== $(date) hibernate skipped (already in progress) ===" >> "$LOG"
            exit 0
        fi
        trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

        pause_sleep_blockers() {
            pkill -SIGSTOP AMPDeviceDiscoveryAgent 2>/dev/null || true
            pkill -SIGSTOP AMPSystemPlayerAgent 2>/dev/null || true
            pkill -SIGSTOP grok-macos-aarch64 2>/dev/null || true
        }

        apply_hibernate_settings() {
            pmset -a hibernatemode 25 >> "$LOG" 2>&1
            pmset -b hibernatemode 25 >> "$LOG" 2>&1
            pmset -c hibernatemode 25 >> "$LOG" 2>&1
            pmset -a standby 0 >> "$LOG" 2>&1
            pmset -b standby 0 >> "$LOG" 2>&1
            pmset -c standby 0 >> "$LOG" 2>&1
            pmset -a autopoweroff 0 >> "$LOG" 2>&1
            pmset -a powernap 0 >> "$LOG" 2>&1
            pmset -a womp 0 >> "$LOG" 2>&1
        }

        echo "=== $(date) hibernate start ===" >> "$LOG"
        pmset -g ps >> "$LOG" 2>&1 || true
        pause_sleep_blockers
        /usr/bin/tmutil stopbackup >> "$LOG" 2>&1 || true
        \(ejectBlock)
        apply_hibernate_settings
        pmset -g custom | grep hibernatemode >> "$LOG" 2>&1 || true
        HIB_BEFORE=$(sysctl -n kern.hibernatecount 2>/dev/null || echo "")
        sleep 2
        pmset sleepnow >> "$LOG" 2>&1
        sleep 15
        HIB_AFTER=$(sysctl -n kern.hibernatecount 2>/dev/null || echo "")
        if [[ -n "$HIB_BEFORE" && -n "$HIB_AFTER" && "$HIB_AFTER" -le "$HIB_BEFORE" ]]; then
            echo "=== $(date) sleepnow did not hibernate (hibernatecount $HIB_BEFORE -> $HIB_AFTER), leaving mode 25 ===" >> "$LOG"
            pkill -SIGCONT grok-macos-aarch64 2>/dev/null || true
            exit 0
        fi
        \(restoreBlock)
        echo "=== $(date) hibernate end ===" >> "$LOG"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let restoreURL = supportDir.appendingPathComponent("restore-after-wake.sh")
        try? FileManager.default.removeItem(at: restoreURL)

        return scriptURL
    }

    private static func runViaAdmin(scriptPath: URL) {
        do {
            try FileManager.default.createDirectory(
                at: logPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let command = "bash '\(scriptPath.path)'"
            let escapedCommand = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let appleScriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges"
            var errorInfo: NSDictionary?
            NSAppleScript(source: appleScriptSource)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                NSLog("Hibernal: hibernate failed: \(errorInfo)")
            }
        } catch {
            NSLog("Hibernal: hibernate setup failed: \(error)")
        }
    }
}