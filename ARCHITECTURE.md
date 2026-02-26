# VisualScanner — Code Architecture

A section-by-section walkthrough of the entire codebase, explaining what each file does and how the pieces connect.

## Table of Contents

- [Data Flow Overview](#data-flow-overview)
- [App Lifecycle](#app-lifecycle)
  - [main.swift](#mainswift)
  - [AppDelegate.swift](#appdelegateswift)
- [Screen Capture](#screen-capture)
  - [ScreenSelector.swift](#screenselectorswift)
  - [ScreenCapturer.swift](#screencapturerswift)
- [OCR Engine](#ocr-engine)
  - [ocr_script.py](#ocr_scriptpy)
  - [TextRecognizer.swift](#textrecognizerswift)
- [User Interface](#user-interface)
  - [StatusBarController.swift](#statusbarcontrollerswift)
  - [ResultWindowController.swift](#resultwindowcontrollerswift)
  - [TranslatableTextView.swift](#translatabletextviewswift)
  - [TranslationBridge.swift](#translationbridgeswift)
  - [EscapableWindow.swift](#escapablewindowswift)
  - [WebPopupController.swift](#webpopupcontrollerswift)
- [Utilities](#utilities)
  - [HotkeyManager.swift](#hotkeymanagerswift)
- [Build Configuration](#build-configuration)
  - [project.yml](#projectyml)

---

## Data Flow Overview

```
User presses Cmd+Shift+J (or clicks menu bar)
        │
        ▼
  StatusBarController
        │
        ▼
  ScreenSelector ──► OverlayWindow (one per display)
        │                    │
        │             User drags to select region
        │                    │
        ▼                    ▼
  ScreenCapturer ◄──── selected NSRect
        │
        ▼
    CGImage (screenshot of region)
        │
        ▼
  TextRecognizer ──► Python subprocess (ocr_script.py)
        │                    │
        │              PaddleOCR processes image
        │                    │
        ▼                    ▼
  Parsed text (String) ◄── JSON output
        │
        ▼
  ResultWindowController ──► TranslationBridge ──► Apple Translation
        │                           │
        ▼                           ▼
  Floating window with          Translated text
  original + translated text
```

---

## App Lifecycle

### main.swift

**Location:** `VisualScanner/App/main.swift`

```swift
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

This is the entry point. Instead of using `@main` or a storyboard, the app is configured manually. The key line is `setActivationPolicy(.accessory)` — this makes VisualScanner a **menu bar-only app**. It won't appear in the Dock or the Cmd+Tab switcher. The app has no main window; it lives entirely in the macOS menu bar.

---

### AppDelegate.swift

**Location:** `VisualScanner/App/AppDelegate.swift`

The app delegate does three things at launch:

1. **Creates the StatusBarController** — this sets up the menu bar icon and all menu items.

2. **Sets up a minimal main menu** with an Edit submenu:
   ```swift
   editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
   editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
   ```
   Without this, `Cmd+C` and `Cmd+A` wouldn't work in the result window's text views. macOS requires a main menu with an Edit submenu for these standard shortcuts to reach `NSTextView` through the responder chain.

3. **Requests Screen Recording permission** by calling `SCShareableContent.excludingDesktopWindows(...)`. This triggers the macOS permission dialog on first launch so the user isn't surprised when they try to capture for the first time. The result is discarded — we just want the side effect.

---

## Screen Capture

### ScreenSelector.swift

**Location:** `VisualScanner/Capture/ScreenSelector.swift`

This file contains three classes that work together to let the user draw a selection rectangle on screen:

#### `ScreenSelector`

The coordinator class. When `start()` is called, it creates one `OverlayWindow` for **each connected display** (supporting multi-monitor setups). When the user completes a selection on any screen, it:
1. Dismisses all overlay windows
2. Waits 100ms for the overlays to visually disappear (so they aren't captured in the screenshot)
3. Calls `ScreenCapturer.capture()` with the selected rectangle

#### `OverlayWindow`

A borderless, transparent `NSWindow` that sits at the `.screenSaver` level (above everything else). It:
- Covers the entire screen
- Has a clear background
- Accepts keyboard events — pressing **Escape** (keyCode 53) cancels the selection
- Converts the selection rectangle from window-local coordinates to screen coordinates before passing it back

#### `SelectionView`

An `NSView` that handles the actual click-and-drag interaction:
- **`mouseDown`** records the starting point
- **`mouseDragged`** calculates the rectangle between the start point and current mouse position, then calls `needsDisplay = true` to trigger a redraw
- **`mouseUp`** finalizes the selection (minimum 5x5 pixels to avoid accidental clicks)
- **`draw`** renders a semi-transparent dark overlay with the selection area cut out, bordered by a white line with a blue dashed inner border
- Sets the cursor to a crosshair via `resetCursorRects`

---

### ScreenCapturer.swift

**Location:** `VisualScanner/Capture/ScreenCapturer.swift`

A single static method that captures a screen region using **ScreenCaptureKit** (Apple's modern screen capture API, replacing the deprecated `CGWindowListCreateImage`).

The main complexity here is **coordinate system conversion**. AppKit uses bottom-left origin (y increases upward), while Core Graphics uses top-left origin (y increases downward). The `convertToCGCoordinates` method handles this:

```swift
y: screenHeight - (rect.origin.y - screen.frame.origin.y) - rect.height
```

The capture configuration sets:
- `sourceRect` to the converted rectangle
- Resolution to match the screen's Retina scale factor (`backingScaleFactor`)
- `showsCursor = false` to exclude the mouse cursor from the capture

There's also an `NSScreen` extension that extracts the `CGDirectDisplayID` from the device description dictionary, which is needed to match an `NSScreen` to an `SCDisplay`.

---

## OCR Engine

### ocr_script.py

**Location:** `VisualScanner/OCR/ocr_script.py`

The Python script that wraps PaddleOCR. It's bundled as a resource in the app bundle and invoked as a subprocess.

#### `init_ocr()`

Initializes PaddleOCR with these settings:
- Suppresses verbose logging (`GLOG_minloglevel=2`, disables DEBUG logging, filters deprecation warnings)
- Uses the `PP-OCRv5_server_rec` model — PaddleOCR's most accurate recognition model
- Disables document orientation classification, unwarping, and textline orientation (not needed for screen captures)

#### `sort_by_layout(texts, dt_polys)`

PaddleOCR returns text regions with polygon coordinates but not necessarily in reading order. This function sorts them intelligently:

1. Calculates the center point and dimensions of each text region from its polygon vertices
2. Determines if the text is **vertical** (majority of regions have height > 1.5x width — common in CJK text)
3. For vertical text: sorts **right-to-left**, then **top-to-bottom** (standard CJK vertical reading order)
4. For horizontal text: sorts **top-to-bottom**, then **left-to-right**

#### `run_ocr(ocr, image_path)`

Processes a single image and returns a JSON string. It handles two PaddleOCR output formats:
- **Dict format** (newer): `{'rec_texts': [...], 'dt_polys': [...]}`  — uses `sort_by_layout` for proper ordering
- **List format** (legacy): `[[polygon, (text, confidence)], ...]` — extracts text directly

The output JSON always has the same shape: `{"success": bool, "text": str, "lines": [str]}`

#### Two Operating Modes

**Single-shot mode** (`python3 ocr_script.py /path/to/image.png`):
- Initializes OCR, processes one image, prints JSON, exits
- ~3-5 second startup delay each time due to model loading

**Server mode** (`python3 ocr_script.py --server`):
- Initializes OCR once, then enters a stdin/stdout loop
- Prints `__READY__` when the model is loaded
- Reads image paths from stdin (one per line)
- Writes JSON result + `__DONE__` sentinel for each image
- Exits cleanly when stdin is closed (EOF)

---

### TextRecognizer.swift

**Location:** `VisualScanner/OCR/TextRecognizer.swift`

The Swift side of the OCR bridge. This is a singleton class (`TextRecognizer.shared`) that manages communication with the Python subprocess.

#### Static API

```swift
static func recognize(from image: CGImage, completion: @escaping (String) -> Void)
```

This is the main entry point. It:
1. Saves the `CGImage` to a temporary PNG file
2. Delegates to either persistent or one-shot mode based on the `keepModelLoaded` setting
3. Cleans up the temp file via `defer`
4. Returns the parsed text on the main thread

#### `keepModelLoaded` Property

A static property backed by `UserDefaults`. Its setter has side effects:
- Setting to `true` calls `warmUp()` to start the persistent Python process
- Setting to `false` calls `stopPersistentProcess()` to terminate it immediately

#### One-Shot Mode (`recognizeOneShot`)

Finds `python3`, runs `ocr_script.py <imagePath>` as a `Process`, waits for it to finish, and parses the JSON output. Simple but slow (~3-5 seconds per scan).

#### Persistent Mode

Three methods manage the persistent process:

- **`warmUp()`** — launches `ensurePersistentProcess()` on a background thread so the model is loaded before the first scan
- **`ensurePersistentProcess()`** — starts the Python process with `--server`, pipes stdin/stdout, and waits for the `__READY__` sentinel. Uses a `NSLock` for thread safety.
- **`recognizeWithPersistentProcess(imagePath:)`** — writes the image path to stdin, reads lines from stdout until `__DONE__`. Falls back to one-shot mode if the process has died.

#### Graceful Shutdown (`stopPersistentProcess`)

```swift
stdinHandle?.closeFile()
process.waitUntilExit()
```

Instead of calling `process.terminate()` (which sends SIGTERM and triggers a macOS "Python quit unexpectedly" crash dialog), we close stdin. This causes Python's `for line in sys.stdin:` loop to receive EOF and exit naturally with code 0.

#### Python Discovery (`findPython3`)

Checks common installation paths in order:
1. `/opt/homebrew/bin/python3` (Apple Silicon Homebrew)
2. `/usr/local/bin/python3` (Intel Homebrew)
3. `/usr/bin/python3` (system Python)
4. Falls back to `which python3`

#### Environment Setup (`buildEnvironment`)

Augments `PATH` with Homebrew and user Python directories. This is critical because when the app is launched from Finder (rather than a terminal), the `PATH` is minimal and won't include Homebrew or pip-installed packages.

#### JSON Parsing (`parseOCRResult`)

PaddleOCR and PaddlePaddle may print warning messages to stdout before the actual JSON. The parser scans each line looking for one that starts with `{` and attempts to parse it as JSON. It extracts the `text` field on success, or logs the `error` field on failure.

---

## User Interface

### StatusBarController.swift

**Location:** `VisualScanner/UI/StatusBarController.swift`

Controls the menu bar icon and dropdown menu.

#### Menu Bar Item

The icon is the Chinese character `掃` (meaning "scan"), set as the button title. The menu contains:
- **Capture Region** (`Cmd+Shift+J`) — triggers a screen capture
- **Keep Model Loaded** — toggle with checkmark, controls persistent Python process
- **Notification Sound** — toggle with checkmark, plays a sound on OCR completion
- **Quit** — stops the persistent process and terminates the app

#### Global Hotkey

Registers `Cmd+Shift+J` (keyCode 38) via `HotkeyManager`. When triggered, calls `performCapture()`.

#### Capture Flow (`performCapture`)

1. Guards against concurrent captures with `isCapturing` flag
2. Creates a `ScreenSelector` and starts it
3. On completion, passes the captured image to `TextRecognizer.recognize()`
4. If text is found: plays a completion sound (if enabled), shows the result window
5. If no text found: shows an alert suggesting the user install PaddleOCR

#### Settings Persistence

- `soundEnabled` — stored in `UserDefaults` under `"notificationSoundEnabled"`, defaults to `true`
- `keepModelLoaded` — delegated to `TextRecognizer.keepModelLoaded`

On launch, if `keepModelLoaded` is enabled, `warmUp()` is called to pre-load the OCR model.

---

### ResultWindowController.swift

**Location:** `VisualScanner/UI/ResultWindowController.swift`

The largest file in the project. Creates and manages the floating result window that displays OCR output.

#### Window Creation (`show(text:)`)

Constructs the entire UI programmatically (no storyboards or XIBs):

**Top button bar:**
- File dropdown (`NSPopUpButton`) — lists `.txt` files in the saved directory
- Save button — appends text to the selected file
- Save As button — opens a save panel
- Speak button — text-to-speech with auto language detection
- Copy button — copies original + translated text to clipboard

**Original text section:**
- Label: "Original"
- Editable `TranslatableTextView` in a scroll view — users can modify the OCR output

**Separator line**

**Translation section:**
- Label: "Translation"
- Language dropdown — 20 languages supported by Apple Translation
- Retranslate button — re-translates with current edits and language selection
- "Keep line breaks" checkbox — controls whether newlines are stripped before translation (off by default)
- Read-only `NSTextView` for the translated output

**Translation bridge:**
Line breaks are stripped from the original text by default before being passed to `TranslationBridge`. The bridge is embedded as an invisible 1x1 pixel `NSHostingView`.

All subviews use `NSUserInterfaceItemIdentifier` strings so they can be located later by the helper class.

#### ResultWindowHelper

A singleton (`ResultWindowHelper.shared`) that handles all button actions via `@objc` methods. It uses a pattern of walking `window.contentView.subviews` and matching identifiers to find specific controls.

**Text extraction** (`textFromWindow`): Iterates subviews to find the two scroll views by their text view identifiers and extracts the current text.

**File management:**
- `populateFilePopup` — scans the saved directory for `.txt` files
- `saveText` — appends original + translated text to the selected file, separated by `---`
- `saveAsText` — opens `NSSavePanel`, saves the directory path to `UserDefaults`, refreshes file popups in all open windows

**Text-to-speech** (`speakText`):
- Uses `AVSpeechSynthesizer`
- Detects the language with `NLLanguageRecognizer` and selects an appropriate voice
- Toggles between "Speak" and "Stop" while playing

**Retranslation** (`performRetranslation`):
- Reads the current original text (which may have been edited)
- Checks the "Keep line breaks" toggle state
- Strips line breaks if the toggle is off
- Reads the target language from the language dropdown
- Removes the old `TranslationBridge` and creates a new one with the updated text and language

**Language selection:**
- 20 languages stored as `(name: String, code: String)` tuples
- Selection persisted in `UserDefaults` under `"targetLanguageCode"`
- Default: English (`"en"`)

---

### TranslatableTextView.swift

**Location:** `VisualScanner/UI/TranslatableTextView.swift`

An `NSTextView` subclass that adds a **"Translate with Google"** option to the right-click context menu. Only appears when text is selected.

When clicked, it:
1. URL-encodes the selected text
2. Constructs a Google Translate URL with `sl=auto` (auto-detect source language)
3. Opens it in an in-app web popup via `WebPopupController`

---

### TranslationBridge.swift

**Location:** `VisualScanner/UI/TranslationBridge.swift`

A SwiftUI view that bridges Apple's Translation framework into the AppKit-based app. This is necessary because the `translationTask` modifier is only available in SwiftUI.

The view is an invisible 1x1 pixel `Color.clear` with two tasks:

1. **`.task` modifier** — runs on appear:
   - Uses `NLLanguageRecognizer` to detect the source language. This is important because without explicit source language detection, the Translation framework shows a system dialog asking the user to pick the source language, which freezes the AppKit event loop.
   - If the detected source language matches the target language, returns the original text unchanged.
   - Otherwise, creates a `TranslationSession.Configuration` with explicit source and target languages.

2. **`.translationTask(config)` modifier** — triggered when `config` is set:
   - Calls `session.translate(text)` with Apple's on-device translation
   - Reports the result (or empty string on failure) via the `onTranslated` callback

The `@available(macOS 15.0, *)` annotation ensures the app compiles on macOS 14 (the Translation framework was introduced in macOS 15).

---

### EscapableWindow.swift

**Location:** `VisualScanner/UI/EscapableWindow.swift`

A simple `NSWindow` subclass that closes when the user presses **Escape**. It overrides two methods:

- `keyDown(with:)` — catches Escape when the window itself has focus
- `cancelOperation(_:)` — catches Escape when an `NSTextView` inside the window has focus (since text views handle Escape through the responder chain's `cancelOperation` method rather than `keyDown`)

Used by both the result window and the web popup window.

---

### WebPopupController.swift

**Location:** `VisualScanner/UI/WebPopupController.swift`

Opens a floating window with a `WKWebView` for in-app web browsing. Currently used only for the "Translate with Google" right-click action. The window:
- Floats above other windows (`.floating` level)
- Is closable, resizable, and miniaturizable
- Loads the provided URL in a full web view
- Stays in memory via the `activeWindows` array (prevents premature deallocation)

---

## Utilities

### HotkeyManager.swift

**Location:** `VisualScanner/Utilities/HotkeyManager.swift`

Implements system-wide (global) keyboard shortcuts using a **CGEvent tap** — a low-level macOS API that intercepts keyboard events before they reach any application. This requires **Accessibility permission**.

#### Registration

```swift
hotkeyManager.register(keyCode: 38, modifiers: [.maskCommand, .maskShift], action: { ... })
hotkeyManager.start()
```

Hotkeys are stored as structs with a keyCode, modifier flags, and a closure.

#### Event Tap Setup (`start`)

Creates a CGEvent tap at the session level that intercepts `keyDown` events. The tap is installed on the current run loop. If creation fails (no Accessibility permission), it calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` to show the system permission dialog.

#### Event Handling (`handleEvent`)

When a key event arrives:
1. Extracts the key code and modifier flags
2. Masks out irrelevant flags (like Caps Lock) to only compare Command, Shift, Option, and Control
3. If a registered hotkey matches, dispatches its action to the main thread and returns `true` (consuming the event so it doesn't reach other apps)

#### Callback Function (`hotkeyCallback`)

A C-function callback (required by the CGEvent API). It:
- Re-enables the tap if macOS disables it due to system load or user input
- Delegates to `handleEvent` via an `Unmanaged` pointer stored as the callback's `userInfo`
- Returns `nil` to consume matched events, or passes them through unchanged

#### Cleanup

`stop()` disables the tap and removes it from the run loop. Called in `deinit`.

---

## Build Configuration

### project.yml

**Location:** `project.yml`

XcodeGen project specification. Key points:

- **Deployment target:** macOS 14.0
- **Swift version:** 5.9
- **No SPM dependencies** — the app uses only system frameworks
- **Python script bundled as a resource:**
  ```yaml
  sources:
    - path: VisualScanner
      excludes:
        - "**/*.py"       # Exclude .py from Swift compilation
    - path: VisualScanner/OCR/ocr_script.py
      buildPhase: resources  # Include as a bundle resource instead
  ```
  This ensures `ocr_script.py` ends up in the app bundle's `Resources` folder and can be located at runtime via `Bundle.main.path(forResource:ofType:)`.

- **Asset catalog:** `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` points to the app icon set
- **Single scheme** for both Debug and Release builds

To regenerate the Xcode project after changes:
```bash
cd VisualScannerApp && xcodegen generate
```
