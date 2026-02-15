# VisualScanner

A macOS menu bar app that captures a region of the screen, runs OCR using [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR), and displays the detected text in a floating window with built-in translation, text-to-speech, and save-to-file.

## Features
![FullDemo](/Examples/FullDemo.gif)

- **Screen region capture** — select any area of the screen with a crosshair overlay
- **PaddleOCR** — accurate text recognition for any language using the PP-OCRv5 server model
- **Vertical text support** — correctly reads vertical CJK text in right-to-left order
- **Editable scanned text** — modify or delete text in the original text area before translating or saving
- **Auto-translation** — translates detected text to English using Apple's Translation framework (macOS 15+)
- **Retranslate** — re-run translation after editing the scanned text
- **Ignore line breaks** — strips OCR line breaks before translating for better results (on by default)
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

## Usage

1. Launch the app — a **VS** icon appears in the menu bar
2. Press `Cmd+Shift+V` or click the menu bar icon and select **Capture Region**
3. Click and drag to select a screen region containing text
4. A floating window appears with the detected text and its English translation
5. Use the toolbar buttons to **Save**, **Speak**, or **Copy** the results

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
