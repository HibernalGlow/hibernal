import CryptoKit
import Foundation

enum PrivilegedHelperManager {
    static let serviceName = "com.hibernatecontrol.helper"
    private static let helperLabel = "com.hibernatecontrol.helper"
    private static let installedPath = "/Library/PrivilegedHelperTools/\(helperLabel)"
    private static let plistPath = "/Library/LaunchDaemons/\(helperLabel).plist"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedPath)
            && FileManager.default.fileExists(atPath: plistPath)
    }

    static var isReady: Bool {
        isInstalled && installedHelperIsCurrent
    }

    /// The version stamp this replaces re-prompted on every release even when the
    /// helper itself was untouched. Byte comparison asks the question that actually
    /// matters: is the installed helper the same binary this build ships?
    private static var installedHelperIsCurrent: Bool {
        guard let embedded = embeddedHelperURL(),
              let shipped = digest(of: embedded),
              let onDisk = digest(of: URL(fileURLWithPath: installedPath))
        else {
            return false
        }
        return shipped == onDisk
    }

    private static func digest(of url: URL) -> SHA256Digest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data)
    }

    static func executeHibernateScript(at path: String, completion: @escaping (Bool) -> Void) {
        ensureReady { ready in
            guard ready else {
                completion(false)
                return
            }
            withHelper { helper, error, close in
                guard let helper else {
                    NSLog("Hibernate Control: helper unavailable: \(error ?? "unknown error")")
                    completion(false)
                    return
                }
                helper.executeHibernateScript(at: path) { success, message in
                    if let message, !message.isEmpty {
                        NSLog("Hibernate Control: helper hibernate error: \(message)")
                    } else if success {
                        NSLog("Hibernate Control: hibernate script launched via helper")
                    }
                    close()
                    completion(success)
                }
            }
        }
    }

    static func setACSleepTimer(minutes: Int, completion: @escaping (Bool) -> Void) {
        ensureReady { ready in
            guard ready else {
                completion(false)
                return
            }
            withHelper { helper, error, close in
                guard let helper else {
                    NSLog("Hibernate Control: helper unavailable: \(error ?? "unknown error")")
                    completion(false)
                    return
                }
                helper.setACSleepTimer(minutes: minutes) { success, message in
                    if let message, !message.isEmpty {
                        NSLog("Hibernate Control: helper pmset error: \(message)")
                    }
                    close()
                    completion(success)
                }
            }
        }
    }

    static func runAdminCommand(_ command: String, label: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let escaped = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScriptSource = "do shell script \"\(escaped)\" with administrator privileges"
            var errorInfo: NSDictionary?
            NSAppleScript(source: appleScriptSource)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                NSLog("Hibernate Control: \(label) failed: \(errorInfo)")
                completion(false)
            } else {
                completion(true)
            }
        }
    }

    private static func ensureReady(completion: @escaping (Bool) -> Void) {
        if isReady {
            kickstartHelperIfNeeded()
            completion(true)
            return
        }
        installHelper { success in
            guard success else {
                completion(false)
                return
            }
            kickstartHelperIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(true)
            }
        }
    }

    private static func installHelper(completion: @escaping (Bool) -> Void) {
        guard let helperSource = embeddedHelperURL()?.path else {
            NSLog("Hibernate Control: embedded helper binary not found in app bundle")
            completion(false)
            return
        }

        let plistContents = launchdPlistContents()
        let tempPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.hibernatecontrol.helper.plist")
        do {
            try plistContents.write(to: tempPlist, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Hibernate Control: failed to stage helper plist: \(error)")
            completion(false)
            return
        }

        let installCommand = """
        launchctl bootout system/\(helperLabel) 2>/dev/null || true
        mkdir -p /Library/PrivilegedHelperTools
        cp '\(helperSource)' '\(installedPath)'
        chown root:wheel '\(installedPath)'
        chmod 544 '\(installedPath)'
        cp '\(tempPlist.path)' '\(plistPath)'
        chown root:wheel '\(plistPath)'
        chmod 644 '\(plistPath)'
        launchctl bootstrap system '\(plistPath)'
        """

        runAdminCommand(installCommand, label: "install privileged helper") { success in
            completion(success)
        }
    }

    private static func embeddedHelperURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/HibernateHelper")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func launchdPlistContents() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(helperLabel)</string>
            <key>MachServices</key>
            <dict>
                <key>\(serviceName)</key>
                <true/>
            </dict>
            <key>Program</key>
            <string>\(installedPath)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(installedPath)</string>
            </array>
        </dict>
        </plist>
        """
    }

    private static func kickstartHelperIfNeeded() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "system/\(helperLabel)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func withHelper(
        _ block: @escaping (HibernateHelperProtocol?, String?, @escaping () -> Void) -> Void
    ) {
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HibernateHelperProtocol.self)

        connection.interruptionHandler = {
            NSLog("Hibernate Control: helper XPC connection interrupted")
        }

        connection.resume()

        let close: () -> Void = {
            connection.invalidate()
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            block(nil, error.localizedDescription, {})
        }) as? HibernateHelperProtocol else {
            close()
            block(nil, "Failed to create helper proxy", {})
            return
        }

        block(proxy, nil, close)
    }
}