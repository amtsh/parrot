import Darwin
import Foundation

/// Prevents two daemon instances from running at once — without this,
/// launching `parrot` while it's already running would spawn a second menu
/// bar icon and a second process racing for the same hotkey tap.
enum RunLock {
    private static let path = "/tmp/parrot.pid"

    /// Returns the PID of an already-running parrot instance, if any. A
    /// stale pidfile (process no longer alive, or PID reused by something
    /// else) is treated as no instance running.
    static func existingPID() -> Int32? {
        guard
            let content = try? String(contentsOfFile: path, encoding: .utf8),
            let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)),
            isParrotProcess(pid)
        else { return nil }
        return pid
    }

    /// Call once this process is the one actually running the daemon.
    static func acquire() {
        try? String(getpid()).write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func release() {
        try? FileManager.default.removeItem(atPath: path)
    }

    private static func isParrotProcess(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 else { return false }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", String(pid), "-o", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return false
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.hasSuffix("parrot")
    }
}
