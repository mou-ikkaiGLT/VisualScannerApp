import Cocoa

class StatusBarController {
    private var statusItem: NSStatusItem
    private var screenSelector: ScreenSelector?
    private var isCapturing = false
    private let hotkeyManager = HotkeyManager()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "VS"
            button.toolTip = "VisualScanner — Click to capture text from screen"
        }

        setupMenu()
        setupGlobalHotkeys()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: "v")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)

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
                    ResultWindowController.show(text: text)
                }
            }
        }
        screenSelector?.start()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
