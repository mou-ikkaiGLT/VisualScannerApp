import Cocoa
import SwiftUI

class ResultWindowController {
    private static var activeWindows: [NSWindow] = []

    static func show(text: String) {
        let window = EscapableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "VisualScanner — Detected Text"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 250, height: 250)

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // Copy button
        let copyButton = NSButton(frame: .zero)
        copyButton.title = "Copy to Clipboard"
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
        NSLayoutConstraint.activate([
            copyButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

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

            translationScroll.topAnchor.constraint(equalTo: translationLabel.bottomAnchor, constant: 4),
            translationScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            translationScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            translationScroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Split space roughly 50/50 between the two scroll views
            originalScroll.heightAnchor.constraint(equalTo: translationScroll.heightAnchor),
        ])

        // --- Translation bridge (invisible SwiftUI helper) ---
        if #available(macOS 15.0, *) {
            let bridge = NSHostingView(rootView: TranslationBridge(
                text: text,
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

// Helper class for button actions (needs to be an NSObject for @objc selectors)
class ResultWindowHelper: NSObject {
    static let shared = ResultWindowHelper()

    @objc func copyText(_ sender: NSButton) {
        guard let window = sender.window,
              let contentView = window.contentView else { return }

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

        var clipText = original
        if !translated.isEmpty {
            clipText += "\n\n" + translated
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clipText, forType: .string)

        // Brief visual feedback
        let title = sender.title
        sender.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            sender.title = title
        }
    }
}
