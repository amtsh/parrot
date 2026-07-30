import Foundation

/// Downloads, verifies, and installs a release tag's binary over
/// /usr/local/bin/parrot. Runs synchronously (network calls block via
/// semaphore) — call from a background queue, never the main thread.
///
/// Replacing the binary needs a privileged rename into a root-owned
/// directory (confirmed: plain `rm`/`mv` there fails without sudo), and a
/// running binary's own file can't be overwritten in place anyway (macOS
/// returns ETXTBSY). `osascript ... with administrator privileges` gives
/// the one-time native admin/Touch ID prompt needed for the atomic swap —
/// the same technique many consumer Mac apps use for self-update.
enum SelfUpdater {
    enum UpdateError: Error {
        case downloadFailed
        case checksumMismatch
        case extractFailed
        case installFailed(Int32)
    }

    private static let asset = "parrot-macos-arm64.tar.gz"

    static func install(tag: String) throws {
        let base = "https://github.com/amtsh/parrot/releases/download/\(tag)"
        guard
            let tarURL = URL(string: "\(base)/\(asset)"),
            let shaURL = URL(string: "\(base)/\(asset).sha256")
        else {
            throw UpdateError.downloadFailed
        }

        let tarData = try download(tarURL)
        let shaData = try download(shaURL)

        guard
            let shaLine = String(data: shaData, encoding: .utf8),
            let expected = shaLine.split(separator: " ").first,
            sha256Hex(tarData) == expected
        else {
            throw UpdateError.checksumMismatch
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parrot-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let tarPath = workDir.appendingPathComponent(asset)
        try tarData.write(to: tarPath)
        try run("/usr/bin/tar", ["-xzf", tarPath.path, "-C", workDir.path])

        let extractedBinary = workDir.appendingPathComponent("parrot")
        guard FileManager.default.fileExists(atPath: extractedBinary.path) else {
            throw UpdateError.extractFailed
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: extractedBinary.path
        )

        let script = """
        xattr -d com.apple.quarantine '\(extractedBinary.path)' 2>/dev/null; \
        mv -f '\(extractedBinary.path)' /usr/local/bin/parrot
        """
        let status = try runOsascript(script)
        guard status == 0 else {
            throw UpdateError.installFailed(status)
        }
    }

    private static func download(_ url: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(UpdateError.downloadFailed)
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data, error == nil {
                result = .success(data)
            } else {
                result = .failure(error ?? UpdateError.downloadFailed)
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    /// Shells out to `shasum` rather than adding a crypto dependency for
    /// one hash — matches how the rest of this codebase favors small
    /// Process calls over extra packages.
    private static func sha256Hex(_ data: Data) -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        guard (try? data.write(to: path)) != nil,
              let output = try? runCapture("/usr/bin/shasum", ["-a", "256", path.path])
        else { return "" }
        return output.split(separator: " ").first.map(String.init) ?? ""
    }

    private static func run(_ launchPath: String, _ args: [String]) throws {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = args
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateError.extractFailed }
    }

    private static func runCapture(_ launchPath: String, _ args: [String]) throws -> String {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runOsascript(_ shellScript: String) throws -> Int32 {
        let escaped = shellScript.replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}
