import AppKit
import ApplicationServices
import ArgumentParser
import AVFoundation
import Darwin
import Foundation
import WhisperKit

@main
struct Parrot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parrot",
        abstract: "Minimal macOS dictation daemon. Hold Fn, speak, release.",
        subcommands: [Run.self, Setup.self, Doctor.self, Models.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the daemon (default)."
    )

    @Flag(name: .long, help: "Skip permission checks at startup.")
    var skipDoctor: Bool = false

    @Flag(name: .long, help: "Print every keyboard event the tap sees (debug).")
    var debugHotkey: Bool = false

    @Flag(name: .long, help: "Write each capture to /tmp/parrot-last.wav for inspection.")
    var dumpWav: Bool = false

    @Flag(name: .long, help: "Disable the on-screen recording overlay.")
    var noOverlay: Bool = false

    @Flag(name: .long, help: "Stay attached to the terminal instead of detaching to the background.")
    var foreground: Bool = false

    @Option(name: .long, help: "Model id to use. Defaults to the last-selected or recommended model.")
    var model: String?

    func run() throws {
        if let pid = RunLock.existingPID() {
            print("parrot is already running (pid \(pid)) — check the menu bar")
            return
        }

        if !foreground && isatty(STDOUT_FILENO) != 0 {
            try daemonize()
            return
        }

        let chosenModel = try resolveModel()

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let toggles = RuntimeToggles(overlayEnabled: !noOverlay)

        let monitor = HotkeyMonitor(debug: debugHotkey)
        let capture = AudioCapture()
        let overlay = MainActor.assumeIsolated { RecordingOverlay() }
        capture.onLevel = { level in overlay.pushLevel(level) }
        let menuBar = MainActor.assumeIsolated {
            MenuBarController(modelID: chosenModel.id, overlayEnabled: toggles.overlayEnabled)
        }

        RunLock.acquire()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            RunLock.release()
        }

        /// Silent — only ever updates the row when it finds something
        /// newer, so a transient network hiccup can't clobber a
        /// previously-found update with a false "up to date."
        func checkForUpdate() {
            UpdateChecker.checkForUpdate { tag in
                guard let tag else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { menuBar.setUpdateAvailable(tag) }
                }
            }
        }
        checkForUpdate()
        let updateTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in
            checkForUpdate()
        }
        _ = updateTimer

        let transcriber = WhisperKitTranscriber(model: chosenModel)
        let warmupSemaphore = DispatchSemaphore(value: 0)
        var warmupError: Error?
        Task.detached {
            do {
                try await transcriber.warmUp()
            } catch {
                warmupError = error
            }
            warmupSemaphore.signal()
        }
        warmupSemaphore.wait()
        if let warmupError {
            FileHandle.standardError.write(Data("warmup failed: \(warmupError)\n".utf8))
            throw ExitCode(1)
        }

        let session = TranscriberSession(initial: transcriber)

        MainActor.assumeIsolated {
            menuBar.onSelectModel = { selected in
                Task {
                    await MainActor.run { menuBar.setModelLoading(selected.displayName) }
                    do {
                        try await session.switchTo(selected)
                        ModelPreference.selectedModelID = selected.id
                        await MainActor.run { menuBar.setActiveModel(selected.id) }
                    } catch {
                        FileHandle.standardError.write(Data("model switch failed: \(error)\n".utf8))
                        await MainActor.run { menuBar.setModelLoadFailed() }
                    }
                }
            }
            menuBar.onToggleOverlay = { enabled in
                toggles.overlayEnabled = enabled
                if !enabled { overlay.hide() }
            }
            menuBar.onToggleLaunchAtLogin = { enabled in
                do {
                    if enabled {
                        try LaunchAgentManager.install()
                    } else {
                        try LaunchAgentManager.uninstall()
                    }
                } catch {
                    FileHandle.standardError.write(Data("launch-at-login change failed: \(error)\n".utf8))
                }
            }
            menuBar.onInstallUpdate = { tag in
                menuBar.setUpdateInstalling()
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try SelfUpdater.install(tag: tag)
                        DispatchQueue.main.async {
                            Self.relaunchSelf(args: self.daemonArguments(skipDoctor: true))
                        }
                    } catch {
                        FileHandle.standardError.write(Data("update failed: \(error)\n".utf8))
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated { menuBar.setUpdateFailed() }
                        }
                    }
                }
            }
        }

        /// Starts the hotkey tap and enters the run loop's event handling.
        /// Only safe to call once accessibility is trusted.
        func startDaemonLoop() throws {
            do {
                try monitor.start { event in
                    switch event {
                    case .pressed:
                        do {
                            try capture.start()
                            FileHandle.standardError.write(Data("● recording\n".utf8))
                            MainActor.assumeIsolated {
                                if toggles.overlayEnabled { overlay.show(.recording) }
                                menuBar.setRecording(true)
                            }
                        } catch {
                            FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
                        }
                    case .released:
                        let samples = capture.stop()
                        MainActor.assumeIsolated {
                            if toggles.overlayEnabled { overlay.show(.transcribing) }
                            menuBar.setTranscribing()
                        }
                        let seconds = Double(samples.count) / AudioCapture.targetSampleRate
                        let rms = computeRMS(samples)
                        FileHandle.standardError.write(Data(
                            String(format: "○ captured %.2fs · rms %.3f\n", seconds, rms).utf8
                        ))
                        if dumpWav, !samples.isEmpty {
                            let path = "/tmp/parrot-last.wav"
                            do {
                                try WAVWriter.write(samples: samples, sampleRate: 16_000, to: path)
                                FileHandle.standardError.write(Data("  wrote \(path)\n".utf8))
                            } catch {
                                FileHandle.standardError.write(Data("  wav write failed: \(error)\n".utf8))
                            }
                        }
                        guard !samples.isEmpty else {
                            MainActor.assumeIsolated {
                                overlay.hide()
                                menuBar.setRecording(false)
                            }
                            return
                        }
                        Task {
                            let started = Date()
                            do {
                                let text = try await session.transcribe(samples)
                                let elapsed = Date().timeIntervalSince(started)
                                FileHandle.standardError.write(Data(
                                    String(format: "→ %.2fs · %@\n", elapsed, text).utf8
                                ))
                                await MainActor.run {
                                    TextInjector.inject(text)
                                    overlay.hide()
                                    menuBar.setRecording(false)
                                }
                            } catch {
                                FileHandle.standardError.write(Data("transcription failed: \(error)\n".utf8))
                                await MainActor.run {
                                    overlay.hide()
                                    menuBar.setRecording(false)
                                }
                            }
                        }
                    }
                }
            } catch {
                FileHandle.standardError.write(Data("failed to register hotkey tap: \(error)\n".utf8))
                throw ExitCode(1)
            }

            let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sigint.setEventHandler {
                FileHandle.standardError.write(Data("\nshutting down\n".utf8))
                monitor.stop()
                NSApp.terminate(nil)
            }
            sigint.resume()
            signal(SIGINT, SIG_IGN)

            FileHandle.standardError.write(Data("listening on fn hold · model: \(chosenModel.id) · ^C to quit\n".utf8))
        }

        // `--skip-doctor` (used by the LaunchAgent, which already ran through
        // setup once) trusts the caller and skips straight to starting —
        // same as before, it just fails loudly if accessibility isn't
        // actually granted.
        if skipDoctor {
            try startDaemonLoop()
            app.run()
            return
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { menuBar.refreshPermissionStatus() }
                }
            }
        }

        if AXIsProcessTrusted() {
            try startDaemonLoop()
        } else {
            // Accessibility isn't granted yet. The menu bar is already up —
            // show its Setup section, trigger the OS prompt, and poll until
            // the grant lands. A trust grant only takes effect for a fresh
            // process, so once it does, relaunch instead of trying to
            // continue in this one.
            MainActor.assumeIsolated { menuBar.setWaitingForPermissions() }
            PermissionActions.promptAccessibility()
            var pollTimer: Timer?
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated { menuBar.refreshPermissionStatus() }
                if AXIsProcessTrusted() {
                    pollTimer?.invalidate()
                    Self.relaunchSelf(args: self.daemonArguments(skipDoctor: true))
                }
            }
        }

        app.run()
    }

    /// Forks a detached background process and returns, freeing the
    /// terminal. Only called when stdout is a TTY, so `parrot install
    /// --launch-at-login` (which runs under launchd, not a terminal) is
    /// unaffected. Permission setup now happens visibly in the child's menu
    /// bar rather than blocking here.
    private func daemonize() throws {
        let process = try Self.spawnSelf(args: daemonArguments(skipDoctor: false))
        print("parrot running in background (pid \(process.processIdentifier))")
        print("check the menu bar bird icon — it'll walk you through any permissions needed")
        print("logs: /tmp/parrot.out.log, /tmp/parrot.err.log")
    }

    /// Spawns a replacement process once accessibility has just been
    /// granted (a trust grant only takes effect for a fresh process), then
    /// terminates this one.
    private static func relaunchSelf(args: [String]) {
        // Release before spawning — otherwise the child's own startup check
        // sees this still-terminating process's PID and thinks a duplicate
        // instance is running.
        RunLock.release()
        guard let process = try? spawnSelf(args: args) else {
            FileHandle.standardError.write(Data("relaunch failed\n".utf8))
            return
        }
        _ = process
        NSApp.terminate(nil)
    }

    private static func spawnSelf(args: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolveExecutablePath())
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = openLogHandle("/tmp/parrot.out.log")
        process.standardError = openLogHandle("/tmp/parrot.err.log")
        try process.run()
        return process
    }

    private func daemonArguments(skipDoctor forceSkipDoctor: Bool) -> [String] {
        var args = ["run", "--foreground"]
        if forceSkipDoctor { args.append("--skip-doctor") }
        if let model {
            args += ["--model", model]
        }
        if debugHotkey { args.append("--debug-hotkey") }
        if dumpWav { args.append("--dump-wav") }
        if noOverlay { args.append("--no-overlay") }
        return args
    }

    /// Resolves the absolute path of the binary currently running, regardless
    /// of whether it was invoked via an absolute path, a relative path, or
    /// found on PATH — so the re-exec'd child always matches this build, not
    /// whatever happens to be installed at /usr/local/bin/parrot.
    private static func resolveExecutablePath() -> String {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [Int8](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return "/usr/local/bin/parrot"
        }
        return String(cString: buffer)
    }

    private static func openLogHandle(_ path: String) -> FileHandle {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = FileHandle(forWritingAtPath: path) ?? FileHandle.nullDevice
        handle.seekToEndOfFile()
        return handle
    }

    private func resolveModel() throws -> TranscriptionModel {
        if let id = model {
            guard let m = ModelRegistry.find(id) else {
                FileHandle.standardError.write(Data("unknown model: \(id)\n".utf8))
                FileHandle.standardError.write(Data("run `parrot models list` to see options.\n".utf8))
                throw ExitCode(1)
            }
            return m
        }
        if let savedID = ModelPreference.selectedModelID, let m = ModelRegistry.find(savedID) {
            return m
        }
        guard let m = ModelRegistry.recommended() else {
            FileHandle.standardError.write(Data("no models registered\n".utf8))
            throw ExitCode(1)
        }
        return m
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, accessibility, and Fn key configuration."
    )

    func run() throws {
        let checks = DoctorReport.run()
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage transcription models.",
        subcommands: [List.self, Download.self]
    )

    struct List: ParsableCommand {
        func run() throws {
            for m in ModelRegistry.shared {
                let star = m.recommended ? "★" : " "
                let id = m.id.padding(toLength: 26, withPad: " ", startingAt: 0)
                let langs = "[\(m.languages.joined(separator: ","))]"
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
                let size = String(format: "%5d MB", m.sizeMB)
                print("\(star) \(id) \(size)  \(langs)  \(m.displayName)")
            }
        }
    }

    struct Download: ParsableCommand {
        @Argument(help: "Model id to download.") var id: String

        func run() throws {
            guard let m = ModelRegistry.find(id) else {
                print("unknown model: \(id)")
                throw ExitCode(1)
            }
            let t = WhisperKitTranscriber(model: m)

            let sem = DispatchSemaphore(value: 0)
            var capturedError: Error?
            Task.detached {
                do { try await t.warmUp() } catch { capturedError = error }
                sem.signal()
            }
            sem.wait()
            if let e = capturedError { throw e }
        }
    }
}
