import AppKit

final class HibernateProgressController {
    static let shared = HibernateProgressController()

    private var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var cancelButton: NSButton?
    private var timer: Timer?
    private var onReady: (() -> Void)?
    private var activeGeneration = 0
    private var waitedSeconds = 0
    private let maxWaitSeconds = 125

    private init() {}

    func begin(generation: Int, onReady: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.finish()
            self.activeGeneration = generation
            self.onReady = onReady
            self.waitedSeconds = 0
            self.showPanel(
                title: NSLocalizedString("Preparing hibernate…", comment: ""),
                detail: NSLocalizedString("Checking system status", comment: "")
            )
            self.evaluateAndContinue()
        }
    }

    func cancel() {
        DispatchQueue.main.async {
            self.finish()
        }
    }

    private func evaluateAndContinue() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        tick()
    }

    private func tick() {
        guard onReady != nil else { return }

        let status = SleepAssertionMonitor.evaluate()

        if !status.blocked {
            showPanel(
                title: NSLocalizedString("Hibernating…", comment: ""),
                detail: NSLocalizedString("Starting now", comment: "")
            )
            complete()
            return
        }

        waitedSeconds += 1
        let remaining = max(0, (status.suggestedWaitSeconds ?? maxWaitSeconds) - waitedSeconds)
        let reason = status.reason ?? NSLocalizedString("Waiting for power cooldown", comment: "")
        let countdown = String(format: NSLocalizedString("Starting in %ds", comment: ""), remaining)
        showPanel(
            title: NSLocalizedString("Preparing hibernate…", comment: ""),
            detail: "\(reason)\n\(countdown)"
        )

        if waitedSeconds >= (status.suggestedWaitSeconds ?? maxWaitSeconds) {
            showPanel(
                title: NSLocalizedString("Hibernating…", comment: ""),
                detail: NSLocalizedString("Starting now", comment: "")
            )
            complete()
        }
    }

    private func complete() {
        guard let ready = onReady else { return }
        finish()
        ready()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        onReady = nil
        panel?.orderOut(nil)
        panel = nil
        titleLabel = nil
        detailLabel = nil
        cancelButton = nil
    }

    @objc private func cancelPressed() {
        HibernateRunner.cancelPending()
        finish()
    }

    private func showPanel(title: String, detail: String) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                styleMask: [.titled, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Hibernal"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.center()

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .boldSystemFont(ofSize: 14)
            titleLabel.alignment = .center
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.alignment = .center
            detailLabel.lineBreakMode = .byWordWrapping
            detailLabel.maximumNumberOfLines = 3
            detailLabel.translatesAutoresizingMaskIntoConstraints = false

            let cancelButton = NSButton(
                title: NSLocalizedString("Cancel", comment: ""),
                target: self,
                action: #selector(cancelPressed)
            )
            cancelButton.bezelStyle = .rounded
            cancelButton.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(titleLabel)
            content.addSubview(detailLabel)
            content.addSubview(cancelButton)
            panel.contentView = content

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
                detailLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                detailLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                cancelButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 12),
                cancelButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ])

            self.panel = panel
            self.titleLabel = titleLabel
            self.detailLabel = detailLabel
            self.cancelButton = cancelButton
        }

        titleLabel?.stringValue = title
        detailLabel?.stringValue = detail
        panel?.orderFrontRegardless()
    }
}

enum SleepAssertionMonitor {
    struct Status {
        var blocked: Bool
        var reason: String?
        var suggestedWaitSeconds: Int?
    }

    static func evaluate() -> Status {
        let output = runPmsetAssertions()
        guard let listed = listedAssertions(from: output) else {
            return Status(blocked: false, reason: nil, suggestedWaitSeconds: nil)
        }

        if listed.contains("hibernate user wake") {
            let timeout = parseTimeoutSeconds(from: output, near: "hibernate user wake")
                ?? parseElapsedRemainingSeconds(from: listed, near: "hibernate user wake", total: 120)
            return Status(
                blocked: true,
                reason: NSLocalizedString("Waiting for post-hibernate cooldown", comment: ""),
                suggestedWaitSeconds: min(timeout.map { $0 + 2 } ?? 120, 125)
            )
        }

        if listed.contains("acwakelinger") {
            let timeout = parseTimeoutSeconds(from: output, near: "acwakelinger")
            return Status(
                blocked: true,
                reason: NSLocalizedString("Waiting for AC power cooldown", comment: ""),
                suggestedWaitSeconds: min(timeout.map { $0 + 2 } ?? 30, 45)
            )
        }

        if listed.contains("darkwakelinger") {
            let timeout = parseTimeoutSeconds(from: output, near: "darkwakelinger")
            return Status(
                blocked: true,
                reason: NSLocalizedString("Waiting for sleep cooldown", comment: ""),
                suggestedWaitSeconds: min(timeout.map { $0 + 2 } ?? 8, 10)
            )
        }

        return Status(blocked: false, reason: nil, suggestedWaitSeconds: nil)
    }

    private static func listedAssertions(from output: String) -> String? {
        guard let range = output.range(of: "Listed by owning process:") else { return nil }
        return String(output[range.upperBound...])
    }

    private static func runPmsetAssertions() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func parseTimeoutSeconds(from output: String, near keyword: String) -> Int? {
        guard let keywordRange = output.range(of: keyword) else { return nil }
        let section = output[keywordRange.lowerBound...]
        let pattern = #"Timeout will fire in (\d+) sec"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsSection = String(section) as NSString
        let range = NSRange(location: 0, length: nsSection.length)
        guard let match = regex.firstMatch(in: nsSection as String, range: range),
              match.numberOfRanges > 1 else { return nil }
        let valueRange = match.range(at: 1)
        return NumberFormatter().number(from: nsSection.substring(with: valueRange))?.intValue
    }

    private static func parseElapsedRemainingSeconds(
        from output: String,
        near keyword: String,
        total: Int
    ) -> Int? {
        guard let keywordRange = output.range(of: keyword) else { return nil }
        let prefix = output[..<keywordRange.lowerBound]
        let pattern = #"\[0x[0-9a-f]+\]\s+(\d\d):(\d\d):(\d\d)\s"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsPrefix = String(prefix) as NSString
        let matches = regex.matches(
            in: nsPrefix as String,
            range: NSRange(location: 0, length: nsPrefix.length)
        )
        guard let last = matches.last, last.numberOfRanges > 3 else { return nil }

        func component(_ index: Int) -> Int {
            let range = last.range(at: index)
            return NumberFormatter().number(from: nsPrefix.substring(with: range))?.intValue ?? 0
        }

        let elapsed = component(1) * 3600 + component(2) * 60 + component(3)
        return max(0, total - elapsed)
    }
}