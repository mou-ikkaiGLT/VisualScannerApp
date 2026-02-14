import Cocoa
import SwiftUI
import AVFoundation
import NaturalLanguage

class ResultWindowController {
    private static var activeWindows: [NSWindow] = []

    static func show(text: String) {
        let window = EscapableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "VisualScanner — Detected Text"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 400, height: 250)

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // --- Top button bar ---

        // File dropdown
        let filePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        filePopup.translatesAutoresizingMaskIntoConstraints = false
        filePopup.identifier = NSUserInterfaceItemIdentifier("filePopup")
        filePopup.target = ResultWindowHelper.shared
        filePopup.action = #selector(ResultWindowHelper.fileSelectionChanged(_:))
        contentView.addSubview(filePopup)
        ResultWindowHelper.shared.populateFilePopup(filePopup)

        // Save button
        let saveButton = NSButton(frame: .zero)
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.target = ResultWindowHelper.shared
        saveButton.action = #selector(ResultWindowHelper.saveText(_:))
        saveButton.identifier = NSUserInterfaceItemIdentifier("saveButton")
        contentView.addSubview(saveButton)

        // Save As button
        let saveAsButton = NSButton(frame: .zero)
        saveAsButton.title = "Save As"
        saveAsButton.bezelStyle = .rounded
        saveAsButton.translatesAutoresizingMaskIntoConstraints = false
        saveAsButton.target = ResultWindowHelper.shared
        saveAsButton.action = #selector(ResultWindowHelper.saveAsText(_:))
        contentView.addSubview(saveAsButton)

        // Speak button
        let speakButton = NSButton(frame: .zero)
        speakButton.title = "Speak"
        speakButton.bezelStyle = .rounded
        speakButton.translatesAutoresizingMaskIntoConstraints = false
        speakButton.target = ResultWindowHelper.shared
        speakButton.action = #selector(ResultWindowHelper.speakText(_:))
        contentView.addSubview(speakButton)

        // Copy button
        let copyButton = NSButton(frame: .zero)
        copyButton.title = "Copy"
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = ResultWindowHelper.shared
        copyButton.action = #selector(ResultWindowHelper.copyText(_:))
        contentView.addSubview(copyButton)

        // --- Original section ---
        let originalLabel = NSTextField(labelWithString: "Original")
        originalLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        originalLabel.textColor = .secondaryLabelColor
        originalLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(originalLabel)

        let originalScroll = NSScrollView(frame: .zero)
        originalScroll.translatesAutoresizingMaskIntoConstraints = false
        originalScroll.hasVerticalScroller = true
        originalScroll.borderType = .noBorder

        let originalTextView = TranslatableTextView(frame: .zero)
        originalTextView.isEditable = false
        originalTextView.isSelectable = true
        originalTextView.font = NSFont.systemFont(ofSize: 16)
        originalTextView.string = text
        originalTextView.textContainerInset = NSSize(width: 8, height: 8)
        originalTextView.isVerticallyResizable = true
        originalTextView.isHorizontallyResizable = false
        originalTextView.autoresizingMask = .width
        originalTextView.textContainer?.widthTracksTextView = true
        originalTextView.identifier = NSUserInterfaceItemIdentifier("originalTextView")
        originalScroll.documentView = originalTextView
        contentView.addSubview(originalScroll)

        // --- Separator ---
        let separator = NSBox(frame: .zero)
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // --- Translation section ---
        let translationLabel = NSTextField(labelWithString: "Translation")
        translationLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        translationLabel.textColor = .secondaryLabelColor
        translationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(translationLabel)

        // Keep line breaks toggle (off by default = line breaks ignored)
        let lineBreakToggle = NSButton(checkboxWithTitle: "Keep line breaks", target: ResultWindowHelper.shared, action: #selector(ResultWindowHelper.toggleLineBreaks(_:)))
        lineBreakToggle.translatesAutoresizingMaskIntoConstraints = false
        lineBreakToggle.controlSize = .small
        lineBreakToggle.font = NSFont.systemFont(ofSize: 11)
        lineBreakToggle.state = .off
        lineBreakToggle.identifier = NSUserInterfaceItemIdentifier("lineBreakToggle")
        contentView.addSubview(lineBreakToggle)

        let translationScroll = NSScrollView(frame: .zero)
        translationScroll.translatesAutoresizingMaskIntoConstraints = false
        translationScroll.hasVerticalScroller = true
        translationScroll.borderType = .noBorder

        let translatedTextView = NSTextView(frame: .zero)
        translatedTextView.isEditable = false
        translatedTextView.isSelectable = true
        translatedTextView.font = NSFont.systemFont(ofSize: 16)
        translatedTextView.string = "Translating…"
        translatedTextView.textColor = .secondaryLabelColor
        translatedTextView.textContainerInset = NSSize(width: 8, height: 8)
        translatedTextView.isVerticallyResizable = true
        translatedTextView.isHorizontallyResizable = false
        translatedTextView.autoresizingMask = .width
        translatedTextView.textContainer?.widthTracksTextView = true
        translatedTextView.identifier = NSUserInterfaceItemIdentifier("translatedTextView")
        translationScroll.documentView = translatedTextView
        contentView.addSubview(translationScroll)

        // --- Layout ---
        // Top row: [filePopup] [Save] [Save As]  ...  [Speak] [Copy]
        NSLayoutConstraint.activate([
            // Left group: file popup
            filePopup.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            filePopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            filePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            // Save + Save As next to popup
            saveButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            saveButton.leadingAnchor.constraint(equalTo: filePopup.trailingAnchor, constant: 6),

            saveAsButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            saveAsButton.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 6),

            // Right group: Speak + Copy
            copyButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            speakButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            speakButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -6),

            // Content below buttons
            originalLabel.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 8),
            originalLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),

            originalScroll.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: 4),
            originalScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            originalScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            separator.topAnchor.constraint(equalTo: originalScroll.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            translationLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            translationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),

            lineBreakToggle.centerYAnchor.constraint(equalTo: translationLabel.centerYAnchor),
            lineBreakToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            translationScroll.topAnchor.constraint(equalTo: translationLabel.bottomAnchor, constant: 4),
            translationScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            translationScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            translationScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            originalScroll.heightAnchor.constraint(equalTo: translationScroll.heightAnchor),
        ])

        // --- Translation bridge (invisible SwiftUI helper) ---
        // Line breaks are ignored by default
        let textForTranslation = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if #available(macOS 15.0, *) {
            let bridge = NSHostingView(rootView: TranslationBridge(
                text: textForTranslation,
                onTranslated: { [weak translatedTextView] translated in
                    guard let tv = translatedTextView else { return }
                    if translated.isEmpty {
                        tv.string = "Translation unavailable"
                    } else {
                        tv.string = translated
                        tv.textColor = .labelColor
                    }
                }
            ))
            bridge.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
            bridge.identifier = NSUserInterfaceItemIdentifier("translationBridge")
            contentView.addSubview(bridge)
        } else {
            translatedTextView.string = "Requires macOS 15 or later"
        }

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        activeWindows.append(window)
    }
}

// MARK: - Helper class for button actions

class ResultWindowHelper: NSObject {
    static let shared = ResultWindowHelper()
    private let synthesizer = AVSpeechSynthesizer()

    private static let directoryKey = "saveDirectoryPath"
    private static let selectedFileKey = "saveSelectedFileName"

    // MARK: - Text extraction

    private func textFromWindow(_ window: NSWindow) -> (original: String, translated: String) {
        guard let contentView = window.contentView else { return ("", "") }

        var original = ""
        var translated = ""

        for subview in contentView.subviews {
            guard let scrollView = subview as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView else { continue }

            switch textView.identifier?.rawValue {
            case "originalTextView":
                original = textView.string
            case "translatedTextView":
                let text = textView.string
                if text != "Translating…" && text != "Translation unavailable" && text != "Requires macOS 15 or later" {
                    translated = text
                }
            default:
                break
            }
        }

        return (original, translated)
    }

    private func filePopup(in window: NSWindow) -> NSPopUpButton? {
        window.contentView?.subviews.first(where: {
            ($0 as? NSPopUpButton)?.identifier?.rawValue == "filePopup"
        }) as? NSPopUpButton
    }

    // MARK: - File popup

    func populateFilePopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        guard let dirPath = UserDefaults.standard.string(forKey: Self.directoryKey),
              FileManager.default.fileExists(atPath: dirPath) else {
            popup.addItem(withTitle: "No folder selected")
            popup.isEnabled = false
            return
        }

        // List .txt files in the directory
        let dirURL = URL(fileURLWithPath: dirPath)
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: dirPath)
                .filter { $0.hasSuffix(".txt") }
                .sorted()
        } catch {
            popup.addItem(withTitle: "No folder selected")
            popup.isEnabled = false
            return
        }

        if files.isEmpty {
            popup.addItem(withTitle: "No .txt files")
            popup.isEnabled = false
            return
        }

        popup.isEnabled = true
        for file in files {
            popup.addItem(withTitle: file)
            popup.lastItem?.representedObject = dirURL.appendingPathComponent(file).path
        }

        // Restore previously selected file
        if let selectedName = UserDefaults.standard.string(forKey: Self.selectedFileKey) {
            popup.selectItem(withTitle: selectedName)
        }
    }

    @objc func fileSelectionChanged(_ sender: NSPopUpButton) {
        if let name = sender.selectedItem?.title {
            UserDefaults.standard.set(name, forKey: Self.selectedFileKey)
        }
    }

    // MARK: - Save

    @objc func saveText(_ sender: NSButton) {
        guard let window = sender.window,
              let popup = filePopup(in: window) else { return }

        // If no folder selected yet, prompt
        guard let path = popup.selectedItem?.representedObject as? String else {
            saveAsText(sender)
            return
        }

        let url = URL(fileURLWithPath: path)
        appendToFile(url: url, window: window, feedbackButton: sender)
    }

    @objc func saveAsText(_ sender: NSButton) {
        guard let window = sender.window else { return }

        let panel = NSSavePanel()
        panel.title = "Save Scanned Text"
        panel.nameFieldStringValue = "scanned_words.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        // Start in saved directory if we have one
        if let dirPath = UserDefaults.standard.string(forKey: Self.directoryKey) {
            panel.directoryURL = URL(fileURLWithPath: dirPath)
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }

            // Remember directory and selected file
            let dirPath = url.deletingLastPathComponent().path
            UserDefaults.standard.set(dirPath, forKey: Self.directoryKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.selectedFileKey)

            // Refresh popup in this window
            if let popup = self.filePopup(in: window) {
                self.populateFilePopup(popup)
            }

            // Also refresh popups in other open windows
            self.refreshAllFilePopups(except: window)

            // Save to the file
            let saveButton = window.contentView?.subviews.first(where: {
                ($0 as? NSButton)?.identifier?.rawValue == "saveButton"
            }) as? NSButton

            self.appendToFile(url: url, window: window, feedbackButton: saveButton)
        }
    }

    private func refreshAllFilePopups(except window: NSWindow) {
        for w in NSApp.windows where w !== window {
            if let popup = filePopup(in: w) {
                populateFilePopup(popup)
            }
        }
    }

    private func appendToFile(url: URL, window: NSWindow, feedbackButton: NSButton?) {
        let (original, translated) = textFromWindow(window)
        guard !original.isEmpty else { return }

        var entry = original
        if !translated.isEmpty {
            entry += "\n" + translated
        }
        entry += "\n---\n"

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try entry.write(to: url, atomically: true, encoding: .utf8)
            }

            // Refresh popup in case a new file was created
            if let popup = filePopup(in: window) {
                populateFilePopup(popup)
            }

            // Brief visual feedback
            let title = feedbackButton?.title ?? "Save"
            feedbackButton?.title = "Saved!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                feedbackButton?.title = title
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to save"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
        }
    }

    // MARK: - Speak

    @objc func speakText(_ sender: NSButton) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            sender.title = "Speak"
            return
        }

        guard let window = sender.window else { return }
        let (original, _) = textFromWindow(window)
        guard !original.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: original)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(original)
        if let lang = recognizer.dominantLanguage {
            if let voice = AVSpeechSynthesisVoice(language: lang.rawValue) {
                utterance.voice = voice
            }
        }

        sender.title = "Stop"
        synthesizer.speak(utterance)

        DispatchQueue.global().async { [weak self] in
            while self?.synthesizer.isSpeaking == true {
                Thread.sleep(forTimeInterval: 0.2)
            }
            DispatchQueue.main.async {
                sender.title = "Speak"
            }
        }
    }

    // MARK: - Toggle line breaks

    @objc func toggleLineBreaks(_ sender: NSButton) {
        guard let window = sender.window,
              let contentView = window.contentView else { return }

        // Get original text
        let (original, _) = textFromWindow(window)
        guard !original.isEmpty else { return }

        // Prepare text for translation
        let textForTranslation: String
        if sender.state == .on {
            // Keep line breaks
            textForTranslation = original
        } else {
            // Ignore line breaks (default)
            textForTranslation = original
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        }

        // Reset translated text view to "Translating…"
        for subview in contentView.subviews {
            guard let scrollView = subview as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView,
                  textView.identifier?.rawValue == "translatedTextView" else { continue }
            textView.string = "Translating…"
            textView.textColor = .secondaryLabelColor
            break
        }

        // Remove existing bridge
        if let oldBridge = contentView.subviews.first(where: {
            $0.identifier?.rawValue == "translationBridge"
        }) {
            oldBridge.removeFromSuperview()
        }

        // Create new bridge with processed text
        if #available(macOS 15.0, *) {
            let translatedTV = contentView.subviews.compactMap({ $0 as? NSScrollView })
                .compactMap({ $0.documentView as? NSTextView })
                .first(where: { $0.identifier?.rawValue == "translatedTextView" })

            let bridge = NSHostingView(rootView: TranslationBridge(
                text: textForTranslation,
                onTranslated: { [weak translatedTV] translated in
                    guard let tv = translatedTV else { return }
                    if translated.isEmpty {
                        tv.string = "Translation unavailable"
                    } else {
                        tv.string = translated
                        tv.textColor = .labelColor
                    }
                }
            ))
            bridge.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
            bridge.identifier = NSUserInterfaceItemIdentifier("translationBridge")
            contentView.addSubview(bridge)
        }
    }

    // MARK: - Copy

    @objc func copyText(_ sender: NSButton) {
        guard let window = sender.window else { return }
        let (original, translated) = textFromWindow(window)

        var clipText = original
        if !translated.isEmpty {
            clipText += "\n\n" + translated
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clipText, forType: .string)

        let title = sender.title
        sender.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            sender.title = title
        }
    }
}
