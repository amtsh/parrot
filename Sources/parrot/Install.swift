import ArgumentParser
import Foundation

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove the launch-at-login LaunchAgent."
    )

    @Flag(name: .long, help: "Register parrot to start at login.")
    var launchAtLogin: Bool = false

    @Flag(name: .long, help: "Remove the launch-at-login agent.")
    var uninstall: Bool = false

    func run() throws {
        if launchAtLogin == uninstall {
            FileHandle.standardError.write(Data(
                "specify exactly one of --launch-at-login or --uninstall\n".utf8
            ))
            throw ExitCode(64)
        }

        if uninstall {
            do {
                try LaunchAgentManager.uninstall()
                print("✓ launch-at-login removed")
            } catch {
                print("nothing to remove")
            }
        } else {
            do {
                try LaunchAgentManager.install()
                let binary = try LaunchAgentManager.resolveBinaryPath()
                print("✓ launch-at-login installed")
                print("  binary: \(binary)")
                print("  logs:   /tmp/parrot.out.log, /tmp/parrot.err.log")
            } catch LaunchAgentError.binaryNotFound {
                FileHandle.standardError.write(Data(
                    "couldn't locate the parrot binary. install it to /usr/local/bin/parrot first.\n".utf8
                ))
                throw ExitCode(1)
            }
        }
    }
}
