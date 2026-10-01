import AppKit
import Carbon

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4849424E), id: 1) // 'HIBN'
    private var eventHandler: EventHandlerUPP!
    private var currentBinding = HotKeyBinding(keyCode: 0, modifierFlags: 0)

    init(callback: @escaping () -> Void) {
        self.callback = callback

        eventHandler = { _, event, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var receivedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &receivedID
            )
            if status == noErr,
               receivedID.signature == manager.hotKeyID.signature,
               receivedID.id == manager.hotKeyID.id {
                DispatchQueue.main.async {
                    NSLog("Hibernal: hotkey pressed")
                    manager.callback()
                }
            }
            return noErr
        }

        installHandler()
    }

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func apply(binding: HotKeyBinding) {
        currentBinding = binding
        reregister()
    }

    func reregister() {
        unregister()
        guard currentBinding.keyCode != 0 else { return }

        let flags = NSEvent.ModifierFlags(rawValue: currentBinding.modifierFlags)
        let modifiers = HotKeyFormatter.carbonModifiers(from: flags)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(currentBinding.keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            NSLog(
                "Hibernal: registered hotkey key=\(currentBinding.keyCode) modifiers=\(modifiers) (\(HotKeyFormatter.displayString(for: currentBinding)))"
            )
        } else {
            NSLog(
                "Hibernal: failed to register hotkey key=\(currentBinding.keyCode) modifiers=\(modifiers) status=\(status)"
            )
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandler,
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
        if status != noErr {
            NSLog("Hibernal: InstallEventHandler failed status=\(status)")
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}