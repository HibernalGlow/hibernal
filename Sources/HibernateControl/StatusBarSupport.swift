import AppKit

enum StatusBarSupport {
    static let toolTip = NSLocalizedString(
        "Hibernate Control — click to open Settings, right-click for menu",
        comment: "Menu bar status item tooltip"
    )

    static func configure(button: NSStatusBarButton, toolTip: String = toolTip) {
        if let image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Hibernate Control") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let sized = image.withSymbolConfiguration(config) ?? image
            sized.isTemplate = true
            button.image = sized
            button.imagePosition = .imageOnly
        } else {
            button.title = "HC"
            button.imagePosition = .noImage
        }
        button.toolTip = toolTip
    }

    static func makeVisible(_ item: NSStatusItem) {
        if #available(macOS 11.0, *) {
            item.isVisible = true
        }
        item.length = NSStatusItem.squareLength
    }
}