import Foundation

private let serviceName = "com.hibernal.helper"
private let allowedScriptName = "hibernate.sh"
private let allowedACSleepMinutes: Set<Int> = [0, 10]

final class HelperImplementation: NSObject, HibernalHelperProtocol {
    func executeHibernateScript(at path: String, with reply: @escaping (Bool, String?) -> Void) {
        guard isAllowedHibernateScript(path) else {
            reply(false, "Rejected script path")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            reply(false, "Script is missing or not executable")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func setACSleepTimer(minutes: Int, with reply: @escaping (Bool, String?) -> Void) {
        guard allowedACSleepMinutes.contains(minutes) else {
            reply(false, "Unsupported AC sleep value")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-c", "sleep", String(minutes)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            reply(process.terminationStatus == 0, process.terminationStatus == 0 ? nil : "pmset failed")
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func isAllowedHibernateScript(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardized.path
        return standardized.hasSuffix("/Hibernal/\(allowedScriptName)")
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HibernalHelperProtocol.self)
        newConnection.exportedObject = HelperImplementation()
        newConnection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: serviceName)
let delegate = HelperDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()