import SwiftUI
import NaturalLanguage

#if canImport(Translation)
import Translation
#endif

/// A tiny invisible SwiftUI view that performs translation via Apple's
/// Translation framework and reports the result through a callback.
/// Uses NLLanguageRecognizer to detect the source language upfront,
/// avoiding the system "choose language" dialog which freezes in AppKit.
@available(macOS 15.0, *)
struct TranslationBridge: View {
    let text: String
    let onTranslated: (String) -> Void
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(config) { session in
                do {
                    let response = try await session.translate(text)
                    await MainActor.run {
                        onTranslated(response.targetText)
                    }
                } catch {
                    await MainActor.run {
                        onTranslated("")
                    }
                }
            }
            .task {
                let target = Locale.Language(identifier: "en")

                // Detect source language to avoid the system language picker dialog
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)

                guard let detected = recognizer.dominantLanguage else {
                    await MainActor.run { onTranslated("") }
                    return
                }

                let source = Locale.Language(identifier: detected.rawValue)

                // Skip if already English
                if source.minimalIdentifier == target.minimalIdentifier {
                    await MainActor.run { onTranslated(text) }
                    return
                }

                config = .init(source: source, target: target)
            }
    }
}
