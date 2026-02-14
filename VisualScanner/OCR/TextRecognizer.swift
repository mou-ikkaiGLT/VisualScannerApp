import Cocoa

struct TextRecognizer {
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

            // 2. Find the bundled Python script
            guard let scriptPath = Bundle.main.path(forResource: "ocr_script", ofType: "py") else {
                print("TextRecognizer: ocr_script.py not found in bundle")
                DispatchQueue.main.async { completion("") }
                return
            }

            // 3. Find python3
            guard let pythonPath = findPython3() else {
                print("TextRecognizer: python3 not found")
                DispatchQueue.main.async { completion("") }
                return
            }

            // 4. Run the script
            let result = runProcess(
                executablePath: pythonPath,
                arguments: [scriptPath, tempURL.path],
                environment: buildEnvironment()
            )

            // 5. Parse JSON output
            let text = parseOCRResult(result)
            DispatchQueue.main.async { completion(text) }
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
