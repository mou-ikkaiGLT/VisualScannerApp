import Cocoa

class TextRecognizer {

    // MARK: - Persistent process state

    static let shared = TextRecognizer()

    private var persistentProcess: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private let processLock = NSLock()
    private var isReady = false

    private static let keepLoadedKey = "keepModelLoaded"

    static var keepModelLoaded: Bool {
        get { UserDefaults.standard.bool(forKey: keepLoadedKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: keepLoadedKey)
            if newValue {
                shared.warmUp()
            } else {
                shared.stopPersistentProcess()
            }
        }
    }

    /// Recognizes text from a CGImage by saving it to a temp file and
    /// running PaddleOCR via a bundled Python script.
    static func recognize(from image: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Save CGImage to a temporary PNG
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")

            guard savePNG(image: image, to: tempURL) else {
                DispatchQueue.main.async { completion("") }
                return
            }

            defer { try? FileManager.default.removeItem(at: tempURL) }

            let text: String
            if keepModelLoaded {
                text = shared.recognizeWithPersistentProcess(imagePath: tempURL.path)
            } else {
                text = recognizeOneShot(imagePath: tempURL.path)
            }

            DispatchQueue.main.async { completion(text) }
        }
    }

    // MARK: - One-shot mode (original behavior)

    private static func recognizeOneShot(imagePath: String) -> String {
        guard let scriptPath = Bundle.main.path(forResource: "ocr_script", ofType: "py") else {
            print("TextRecognizer: ocr_script.py not found in bundle")
            return ""
        }
        guard let pythonPath = findPython3() else {
            print("TextRecognizer: python3 not found")
            return ""
        }

        let result = runProcess(
            executablePath: pythonPath,
            arguments: [scriptPath, imagePath],
            environment: buildEnvironment()
        )
        return parseOCRResult(result)
    }

    // MARK: - Persistent process mode

    /// Pre-launch the Python process so the model is loaded and ready.
    func warmUp() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.ensurePersistentProcess()
        }
    }

    func stopPersistentProcess() {
        processLock.lock()
        defer { processLock.unlock() }
        if let process = persistentProcess, process.isRunning {
            // Close stdin so the Python script's stdin loop ends naturally
            // and it exits with code 0 (no crash dialog)
            stdinHandle?.closeFile()
            process.waitUntilExit()
        }
        persistentProcess = nil
        stdinHandle = nil
        stdoutHandle = nil
        isReady = false
    }

    private func ensurePersistentProcess() {
        processLock.lock()
        defer { processLock.unlock() }

        // Already running and ready
        if let process = persistentProcess, process.isRunning, isReady {
            return
        }

        // Clean up dead process
        persistentProcess = nil
        stdinHandle = nil
        stdoutHandle = nil
        isReady = false

        guard let scriptPath = Bundle.main.path(forResource: "ocr_script", ofType: "py") else {
            print("TextRecognizer: ocr_script.py not found in bundle")
            return
        }
        guard let pythonPath = Self.findPython3() else {
            print("TextRecognizer: python3 not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "--server"]
        process.environment = Self.buildEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            print("TextRecognizer: Failed to start persistent process: \(error)")
            return
        }

        persistentProcess = process
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading

        // Wait for __READY__ sentinel
        if let line = readLine(from: stdoutPipe.fileHandleForReading),
           line.contains("__READY__") {
            isReady = true
            print("TextRecognizer: Persistent process ready")
        } else {
            print("TextRecognizer: Persistent process failed to become ready")
            process.terminate()
            persistentProcess = nil
        }
    }

    private func recognizeWithPersistentProcess(imagePath: String) -> String {
        processLock.lock()

        // Ensure process is running
        if persistentProcess == nil || !persistentProcess!.isRunning || !isReady {
            processLock.unlock()
            ensurePersistentProcess()
            processLock.lock()
        }

        guard let stdin = stdinHandle, let stdout = stdoutHandle, isReady else {
            processLock.unlock()
            // Fall back to one-shot
            return Self.recognizeOneShot(imagePath: imagePath)
        }

        // Send image path
        let command = imagePath + "\n"
        stdin.write(command.data(using: .utf8)!)

        // Read lines until __DONE__ sentinel
        var output = ""
        while let line = readLine(from: stdout) {
            if line.contains("__DONE__") {
                break
            }
            output += line + "\n"
        }

        processLock.unlock()

        return Self.parseOCRResult(output)
    }

    /// Read a single line from a file handle (blocking).
    private func readLine(from handle: FileHandle) -> String? {
        var lineData = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty { return nil } // EOF
            if byte[0] == 0x0A { // newline
                return String(data: lineData, encoding: .utf8)
            }
            lineData.append(byte)
        }
    }

    // MARK: - Image saving

    private static func savePNG(image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: - Python discovery

    private static func findPython3() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: try `which python3`
        let result = runProcess(executablePath: "/usr/bin/which", arguments: ["python3"], environment: buildEnvironment())
        let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    // MARK: - Environment

    private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Augment PATH so paddleocr and its dependencies are found
        // when the app is launched from Finder (which has a minimal PATH)
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/sbin",
            NSHomeDirectory() + "/Library/Python/3.11/bin",
            NSHomeDirectory() + "/Library/Python/3.12/bin",
            NSHomeDirectory() + "/Library/Python/3.13/bin",
            NSHomeDirectory() + "/.local/bin",
        ]

        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        return env
    }

    // MARK: - Process execution

    private static func runProcess(executablePath: String, arguments: [String], environment: [String: String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("TextRecognizer: Failed to run process: \(error)")
            return ""
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if let stderrString = String(data: stderrData, encoding: .utf8), !stderrString.isEmpty {
            print("TextRecognizer stderr: \(stderrString)")
        }

        if process.terminationStatus != 0 {
            print("TextRecognizer: Process exited with status \(process.terminationStatus)")
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - JSON parsing

    private static func parseOCRResult(_ rawOutput: String) -> String {
        // PaddleOCR/PaddlePaddle may print noise to stdout before our JSON.
        // Look for the line containing our JSON marker.
        let lines = rawOutput.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { continue }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let success = json["success"] as? Bool, success,
                       let text = json["text"] as? String {
                        return text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let error = json["error"] as? String {
                        print("TextRecognizer: OCR error: \(error)")
                    }
                    return ""
                }
            } catch {
                continue
            }
        }

        print("TextRecognizer: No valid JSON found in output: \(rawOutput)")
        return ""
    }
}
