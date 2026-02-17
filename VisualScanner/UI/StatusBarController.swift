import Cocoa
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private var screenSelector: ScreenSelector?
    private var isCapturing = false
    private let hotkeyManager = HotkeyManager()

    private static let soundEnabledKey = "notificationSoundEnabled"
    private var soundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.soundEnabledKey) == nil {
                return true // default on
            }
            return UserDefaults.standard.bool(forKey: Self.soundEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.soundEnabledKey) }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "掃"
            button.toolTip = "VisualScanner — Click to capture text from screen"
        }

        setupMenu()
        setupGlobalHotkeys()

        // Warm up persistent process if enabled
        if TextRecognizer.keepModelLoaded {
            TextRecognizer.shared.warmUp()
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: "v")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        let keepLoadedItem = NSMenuItem(title: "Keep Model Loaded", action: #selector(toggleKeepLoaded(_:)), keyEquivalent: "")
        keepLoadedItem.target = self
        keepLoadedItem.state = TextRecognizer.keepModelLoaded ? .on : .off
        menu.addItem(keepLoadedItem)

        let soundItem = NSMenuItem(title: "Notification Sound", action: #selector(toggleSound(_:)), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = soundEnabled ? .on : .off
        menu.addItem(soundItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupGlobalHotkeys() {
        // Cmd+Shift+V → Capture region
        // V = keyCode 9
        hotkeyManager.register(
            keyCode: 9,
            modifiers: CGEventFlags([.maskCommand, .maskShift]),
            action: { [weak self] in self?.performCapture() }
        )

        hotkeyManager.start()
    }

    @objc private func captureRegion() {
        performCapture()
    }

    private func performCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        screenSelector = ScreenSelector { [weak self] capturedImage in
            self?.screenSelector = nil
            self?.isCapturing = false
            guard let image = capturedImage else { return }

            TextRecognizer.recognize(from: image) { text in
                DispatchQueue.main.async {
                    guard !text.isEmpty else {
                        let alert = NSAlert()
                        alert.messageText = "No text detected"
                        alert.informativeText = "No text was found in the selected region.\n\nMake sure Python 3 and PaddleOCR are installed:\n  pip3 install paddleocr paddlepaddle"
                        alert.alertStyle = .informational
                        alert.runModal()
                        return
                    }
                    self?.playCompletionSound()
                    ResultWindowController.show(text: text)
                }
            }
        }
        screenSelector?.start()
    }

    @objc private func toggleKeepLoaded(_ sender: NSMenuItem) {
        let newValue = !TextRecognizer.keepModelLoaded
        TextRecognizer.keepModelLoaded = newValue
        sender.state = newValue ? .on : .off
    }

    @objc private func toggleSound(_ sender: NSMenuItem) {
        soundEnabled.toggle()
        sender.state = soundEnabled ? .on : .off
    }

    private func playCompletionSound() {
        guard soundEnabled else { return }
        NSSound(named: "Glass")?.play()
    }

    @objc private func quit() {
        TextRecognizer.shared.stopPersistentProcess()
        NSApplication.shared.terminate(nil)
    }
}
