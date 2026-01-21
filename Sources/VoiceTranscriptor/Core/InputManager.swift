import Cocoa
import CoreGraphics
import Combine

class InputManager: ObservableObject {
    enum KeyAction {
        case startMic
        case stopMic
        case startSystem
        case stopSystem
    }

    let keyActionSubject = PassthroughSubject<KeyAction, Never>()

    // Default Key codes (Can be made configurable)
    // Using F1 and F2 by default to prevent "hijacking" common typing keys X/Y.
    // 122 = F1
    // 120 = F2
    private var micKeyCode: CGKeyCode = 122
    private var sysKeyCode: CGKeyCode = 120

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State to handle "Press and Hold" (prevent autorepeat triggering multiple starts)
    private var isMicKeyDown = false
    private var isSysKeyDown = false

    init() {
        // Load initial values from UserDefaults or use defaults
        let mic = UserDefaults.standard.integer(forKey: "micKeyCode")
        let sys = UserDefaults.standard.integer(forKey: "sysKeyCode")

        if mic != 0 { self.micKeyCode = CGKeyCode(mic) }
        if sys != 0 { self.sysKeyCode = CGKeyCode(sys) }

        setupEventTap()
    }

    func updateKeyBindings(mic: Int, sys: Int) {
        self.micKeyCode = CGKeyCode(mic)
        self.sysKeyCode = CGKeyCode(sys)
    }

    private func setupEventTap() {
        // Accessibility permission check
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !accessEnabled {
            print("Accessibility access not granted. Please enable in System Settings.")
            // In a real app, show UI alert here or handle gracefully
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        func callback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<InputManager>.fromOpaque(refcon).takeUnretainedValue()

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            if type == .keyDown {
                if keyCode == manager.micKeyCode {
                    if !manager.isMicKeyDown {
                        manager.isMicKeyDown = true
                        manager.keyActionSubject.send(.startMic)
                        return nil // Consume event? Maybe not if we want other apps to receive it too. Let's pass it for now unless we want to block it.
                    }
                } else if keyCode == manager.sysKeyCode {
                    if !manager.isSysKeyDown {
                        manager.isSysKeyDown = true
                        manager.keyActionSubject.send(.startSystem)
                        return nil
                    }
                }
            } else if type == .keyUp {
                if keyCode == manager.micKeyCode {
                    if manager.isMicKeyDown {
                        manager.isMicKeyDown = false
                        manager.keyActionSubject.send(.stopMic)
                        return nil
                    }
                } else if keyCode == manager.sysKeyCode {
                    if manager.isSysKeyDown {
                        manager.isSysKeyDown = false
                        manager.keyActionSubject.send(.stopSystem)
                        return nil
                    }
                }
            }

            return Unmanaged.passUnretained(event)
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfPointer
        ) else {
            print("Failed to create event tap")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap, true)
        }
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap, false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
}
