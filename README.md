# VisualScanner

A macOS menu bar app that captures a region of the screen, runs OCR using [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR), and displays the detected text in a floating window with built-in translation, text-to-speech, and save-to-file. Useful when you need to read any text that cannot be automatically transcribed, such as epub files, online videos, or video games!

![Full Demo](/Examples/Fullvideo.gif)

## Features

### Screen Capture and OCR

Press `Cmd+Shift+J` or click the menu bar icon to select any region of the screen. VisualScanner uses PaddleOCR's PP-OCRv5 server model for accurate text recognition across any language, with automatic reading order detection for vertical CJK text.

![Capture Example](/Examples/capture.gif)

### Translation

Detected text is automatically translated using Apple's Translation framework (macOS 15+). Choose from 20 target languages with the dropdown selector. Line breaks from OCR are stripped by default for cleaner translations.

![Translation Example](/Examples/translation.gif)

### Edit and Retranslate

The scanned text is fully editable. Make corrections or remove unwanted text, then click **Retranslate** to update the translation with your changes.

![Edit Example](/Examples/edit.gif)

### Save, Speak, and Copy

Save scanned text and translations to `.txt` files using the built-in file picker. Use text-to-speech with automatic language detection, or copy everything to the clipboard. Right-click the original text to open it in Google Translate.

![Toolbar Example](/Examples/toolbar.gif)

### Menu Bar Options

![Menu Bar Example](/Examples/menubar.gif)

- **Keep Model Loaded** — keep PaddleOCR in memory for faster scans (see [note on memory usage](#keep-model-loaded))
- **Notification Sound** — plays a sound when OCR completes

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
- **Accessibility** — needed for the global hotkey (`Cmd+Shift+J`) to work via CGEvent tap. You will be prompted to grant this in System Settings > Privacy & Security > Accessibility.

The app is not sandboxed, as it needs to invoke the system Python installation to run PaddleOCR.

## Keep Model Loaded

By default, VisualScanner spawns a new Python process for each scan, which includes a ~3-5 second delay while PaddleOCR loads its models. Enabling **Keep Model Loaded** from the menu bar keeps the PaddleOCR process running in the background so subsequent scans are near-instant.

**Memory impact:** The persistent Python process holds the OCR models in memory, using approximately **300-500MB of RAM** while idle. The process consumes no CPU when not actively scanning. When disabled, the process is terminated immediately and the memory is freed.

## Changing the Hotkey

If the default hotkey for this app is (`Cmd+Shift+J`), however if you frequently use this hotkey for another app, you can manually change the hotkey as follows:
The global capture hotkey (`Cmd+Shift+J`) is defined in [`VisualScanner/UI/StatusBarController.swift` at line 60](VisualScanner/UI/StatusBarController.swift#L60). Change the `keyCode` and `modifiers` values, then rebuild. macOS key codes can be found [here](https://eastmanreference.com/complete-list-of-applescript-key-codes).

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
    ├── Assets.xcassets         # App icon
    ├── Info.plist
    └── VisualScanner.entitlements
```
