# VisualScanner

A macOS menu bar app that captures a region of the screen, runs OCR using [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR), and displays the detected text in a floating window with built-in translation, text-to-speech, and save-to-file.

## Features
![FullDemo](/Examples/FullDemo.gif)

- **Screen region capture** — select any area of the screen with a crosshair overlay
- **PaddleOCR** — accurate text recognition for any language using the PP-OCRv5 server model
- **Vertical text support** — correctly reads vertical CJK text in right-to-left order
- **Editable scanned text** — modify or delete text in the original text area before translating or saving
- **Auto-translation** — translates detected text using Apple's Translation framework (macOS 15+) with a target language selector supporting 20 languages
- **Retranslate** — re-run translation after editing the scanned text or changing the target language
- **Ignore line breaks** — strips OCR line breaks before translating for better results (on by default)
- **Keep Model Loaded** — optionally keep the PaddleOCR model in memory for faster subsequent scans (see [note on memory usage](#keep-model-loaded))
- **Notification sound** — plays a sound when OCR completes (toggleable from the menu bar)
- **Text-to-speech** — speaks the original text with language-appropriate voice selection
- **Save to file** — save scanned text and translations to `.txt` files with a persistent file/folder picker
- **Copy to clipboard** — copies original and translated text
- **Google Translate** — right-click the original text to open in Google Translate
- **Global hotkey** — `Cmd+Shift+V` triggers capture from anywhere

## Requirements

- macOS 14.0 or later (macOS 15+ for translation)
- Python 3
- PaddleOCR and PaddlePaddle:

```bash
pip3 install paddleocr paddlepaddle
```

## Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project.

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
cd VisualScannerApp
xcodegen generate

# Build from command line
xcodebuild -project VisualScanner.xcodeproj -scheme VisualScanner -configuration Release build
```

Or open `VisualScanner.xcodeproj` in Xcode and build from there.

### Creating a DMG

```bash
# Build Release first, then:
./build-dmg.sh
```

The DMG will be created on your Desktop. Recipients should right-click and select Open on first launch. If they get a "damaged" error:

```bash
xattr -cr /Applications/VisualScanner.app
```

## Permissions

VisualScanner requires the following macOS permissions to function:

- **Screen Recording** — needed to capture screen regions via ScreenCaptureKit. You will be prompted to grant this in System Settings > Privacy & Security > Screen Recording on first use.
- **Accessibility** — needed for the global hotkey (`Cmd+Shift+V`) to work via CGEvent tap. You will be prompted to grant this in System Settings > Privacy & Security > Accessibility.

The app is not sandboxed, as it needs to invoke the system Python installation to run PaddleOCR.

## Usage

1. Launch the app — a **VS** icon appears in the menu bar
2. Press `Cmd+Shift+V` or click the menu bar icon and select **Capture Region**
3. Click and drag to select a screen region containing text
4. A floating window appears with the detected text and its translation
5. Use the target language dropdown to change the translation language
6. Edit the scanned text and click **Retranslate** to update the translation
7. Use the toolbar buttons to **Save**, **Speak**, or **Copy** the results

The menu bar dropdown also provides toggles for **Keep Model Loaded** and **Notification Sound**.

## Keep Model Loaded

By default, VisualScanner spawns a new Python process for each scan, which includes a ~3-5 second delay while PaddleOCR loads its models. Enabling **Keep Model Loaded** from the menu bar keeps the PaddleOCR process running in the background so subsequent scans are near-instant.

**Memory impact:** The persistent Python process holds the OCR models in memory, using approximately **300-500MB of RAM** while idle. The process consumes no CPU when not actively scanning. When disabled, the process is terminated immediately and the memory is freed.

## Changing the Hotkey

The global capture hotkey (`Cmd+Shift+V`) is defined in [`VisualScanner/UI/StatusBarController.swift` at line 60](VisualScanner/UI/StatusBarController.swift#L60). Change the `keyCode` and `modifiers` values, then rebuild. macOS key codes can be found [here](https://eastmanreference.com/complete-list-of-applescript-key-codes).

## Project Structure

```
VisualScanner/
├── App/
│   ├── main.swift              # Entry point
│   └── AppDelegate.swift       # App lifecycle
├── Capture/
│   ├── ScreenSelector.swift    # Crosshair overlay for region selection
│   └── ScreenCapturer.swift    # ScreenCaptureKit capture
├── OCR/
│   ├── ocr_script.py           # PaddleOCR wrapper (bundled resource)
│   └── TextRecognizer.swift    # Python subprocess bridge
├── UI/
│   ├── StatusBarController.swift       # Menu bar item and hotkey
│   ├── ResultWindowController.swift    # Result window with all controls
│   ├── TranslatableTextView.swift      # NSTextView with right-click translate
│   ├── TranslationBridge.swift         # SwiftUI bridge to Apple Translation
│   ├── EscapableWindow.swift           # NSWindow that closes on Escape
│   └── WebPopupController.swift        # In-app web popup for Google Translate
├── Utilities/
│   └── HotkeyManager.swift    # Global hotkey via CGEvent tap
└── Resources/
    ├── Info.plist
    └── VisualScanner.entitlements
```
