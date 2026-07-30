import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and provides the only persistent control surface for the daemon
/// (since we run as `.accessory` — no dock icon, no main window).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let modelLabel: NSMenuItem
    private let stateLabel: NSMenuItem
    private let modelMenu: NSMenu
    private var modelItems: [String: NSMenuItem] = [:]
    private var activeModelID: String

    private let overlayItem: NSMenuItem
    private let launchAtLoginItem: NSMenuItem
    private let versionItem: NSMenuItem
    private var availableUpdateTag: String?
    private var isDevBuild: Bool { parrotVersion == "dev" }

    private let permissionsMenu: NSMenu
    private let accessibilityItem: NSMenuItem
    private let microphoneItem: NSMenuItem
    private let fnKeySeparator: NSMenuItem
    private let fnKeyItem: NSMenuItem

    var onSelectModel: (TranscriptionModel) -> Void = { _ in }
    var onToggleOverlay: (Bool) -> Void = { _ in }
    var onToggleLaunchAtLogin: (Bool) -> Void = { _ in }
    var onInstallUpdate: (String) -> Void = { _ in }
    var onCheckForUpdate: () -> Void = {}

    init(modelID: String, overlayEnabled: Bool) {
        self.activeModelID = modelID
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        overlayItem = NSMenuItem(title: "Recording Overlay", action: nil, keyEquivalent: "")
        overlayItem.state = overlayEnabled ? .on : .off
        launchAtLoginItem = NSMenuItem(title: "Start at Login", action: nil, keyEquivalent: "")
        versionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Order is deliberate, grouped by how often each row actually
        // matters: live status, then the controls people actually click,
        // then one-time setup/diagnostics, then set-and-forget config,
        // then Quit last.
        stateLabel = NSMenuItem(title: "idle · hold fn to dictate", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        modelLabel = NSMenuItem(title: "model: \(modelID)", action: nil, keyEquivalent: "")
        modelLabel.isEnabled = false
        menu.addItem(modelLabel)

        modelMenu = NSMenu()
        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        menu.addItem(modelMenuItem)
        menu.setSubmenu(modelMenu, for: modelMenuItem)

        menu.addItem(overlayItem)

        menu.addItem(.separator())

        permissionsMenu = NSMenu()
        accessibilityItem = NSMenuItem(title: "Accessibility", action: nil, keyEquivalent: "")
        microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        permissionsMenu.addItem(accessibilityItem)
        permissionsMenu.addItem(microphoneItem)
        let permissionsMenuItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        menu.addItem(permissionsMenuItem)
        menu.setSubmenu(permissionsMenu, for: permissionsMenuItem)

        fnKeySeparator = .separator()
        fnKeyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(fnKeySeparator)
        menu.addItem(fnKeyItem)

        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(versionItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit parrot", action: nil, keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu

        super.init()

        menu.delegate = self
        overlayItem.target = self
        overlayItem.action = #selector(overlayClicked)
        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(launchAtLoginClicked)
        accessibilityItem.target = self
        accessibilityItem.action = #selector(accessibilityClicked)
        microphoneItem.target = self
        microphoneItem.action = #selector(microphoneClicked)
        fnKeyItem.target = self
        fnKeyItem.action = #selector(fnKeyClicked)
        permissionsMenu.delegate = self
        versionItem.target = self
        versionItem.action = #selector(versionClicked)
        quit.target = self
        quit.action = #selector(quitClicked)

        configureButton(recording: false)
        rebuildModelMenu()
        refreshPermissionStatus()
        refreshVersionItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = LaunchAgentManager.isInstalled() ? .on : .off
        refreshPermissionStatus()
    }

    /// Re-reads accessibility/microphone/fn-key status. The Permissions
    /// submenu items reflect grant state as checkmarks; the fn-key item
    /// (not a revocable permission, so it doesn't belong in that submenu)
    /// hides itself once the mapping is correct. Safe to call from anywhere,
    /// including a background poll timer.
    func refreshPermissionStatus() {
        let checks = DoctorReport.run()
        let accessibilityOK = isOK(checks, "accessibility")
        let microphoneOK = isOK(checks, "microphone")
        let fnKeyOK = isOK(checks, "fn key mapping")

        accessibilityItem.state = accessibilityOK ? .on : .off
        microphoneItem.state = microphoneOK ? .on : .off
        fnKeyItem.title = fnKeyOK ? "✓ Fn Key Mapping" : "✗ Fix Fn Key Mapping…"
        fnKeyItem.isHidden = fnKeyOK
        fnKeySeparator.isHidden = fnKeyOK
    }

    private func isOK(_ checks: [Check], _ name: String) -> Bool {
        guard let check = checks.first(where: { $0.name == name }) else { return false }
        if case .ok = check.status { return true }
        return false
    }

    /// Call while the daemon can't start yet because accessibility hasn't
    /// been granted.
    func setWaitingForPermissions() {
        stateLabel.title = "waiting for permissions — see below"
        refreshPermissionStatus()
    }

    @objc private func accessibilityClicked() {
        if accessibilityItem.state == .on {
            // Can't revoke programmatically — open the pane to do it manually.
            PermissionActions.openAccessibilitySettings()
        } else {
            PermissionActions.promptAccessibility()
        }
        refreshPermissionStatus()
    }

    @objc private func microphoneClicked() {
        if microphoneItem.state == .on {
            // Can't revoke programmatically — open the pane to do it manually.
            PermissionActions.openMicrophoneSettings()
            refreshPermissionStatus()
        } else {
            PermissionActions.requestMicrophone { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    MainActor.assumeIsolated { self.refreshPermissionStatus() }
                }
            }
        }
    }

    @objc private func fnKeyClicked() {
        PermissionActions.openKeyboardSettings()
    }

    @objc private func overlayClicked() {
        let enabled = overlayItem.state != .on
        overlayItem.state = enabled ? .on : .off
        onToggleOverlay(enabled)
    }

    @objc private func launchAtLoginClicked() {
        let enabled = launchAtLoginItem.state != .on
        onToggleLaunchAtLogin(enabled)
        launchAtLoginItem.state = LaunchAgentManager.isInstalled() ? .on : .off
    }

    /// Reflects current update state: dev builds show a disabled "Version:
    /// dev"; otherwise shows an install prompt if an update was found, or
    /// "Version: vX.Y.Z (up to date)" — clicking either checks or installs.
    private func refreshVersionItem() {
        if isDevBuild {
            versionItem.title = "Version: dev"
            versionItem.isEnabled = false
        } else if let tag = availableUpdateTag {
            versionItem.title = "★ Update to \(tag) available"
            versionItem.isEnabled = true
        } else {
            versionItem.title = "Version: \(parrotVersion) (up to date)"
            versionItem.isEnabled = true
        }
    }

    /// Call while a manually-triggered check is in flight.
    func setCheckingForUpdate() {
        versionItem.title = "Checking for updates…"
        versionItem.isEnabled = false
    }

    /// Call when UpdateChecker finds a newer release.
    func setUpdateAvailable(_ tag: String) {
        availableUpdateTag = tag
        refreshVersionItem()
    }

    /// Call when a check completes and nothing newer was found.
    func setUpToDate() {
        availableUpdateTag = nil
        refreshVersionItem()
    }

    /// Call while the update is downloading/installing.
    func setUpdateInstalling() {
        versionItem.title = "Updating…"
        versionItem.isEnabled = false
    }

    /// Call if the install fails; reverts to the clickable "available" state
    /// (still holding the same tag) so the user can retry.
    func setUpdateFailed() {
        refreshVersionItem()
    }

    @objc private func versionClicked() {
        if let tag = availableUpdateTag {
            onInstallUpdate(tag)
        } else if !isDevBuild {
            onCheckForUpdate()
        }
    }

    private func rebuildModelMenu() {
        modelMenu.removeAllItems()
        modelItems.removeAll()
        for candidate in ModelRegistry.shared {
            let item = NSMenuItem(
                title: candidate.displayName,
                action: #selector(modelClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = candidate.id
            item.state = candidate.id == activeModelID ? .on : .off
            modelMenu.addItem(item)
            modelItems[candidate.id] = item
        }
    }

    @objc private func modelClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              id != activeModelID,
              let candidate = ModelRegistry.find(id)
        else { return }
        onSelectModel(candidate)
    }

    /// Call once a model switch has finished loading and become active.
    func setActiveModel(_ id: String) {
        activeModelID = id
        modelLabel.title = "model: \(id)"
        for (candidateID, item) in modelItems {
            item.state = candidateID == id ? .on : .off
        }
    }

    /// Call while a model switch is downloading/loading.
    func setModelLoading(_ displayName: String) {
        modelLabel.title = "model: loading \(displayName)…"
    }

    /// Call when a model switch fails; reverts the label to the still-active model.
    func setModelLoadFailed() {
        modelLabel.title = "model: \(activeModelID)"
    }

    func setRecording(_ recording: Bool) {
        stateLabel.title = recording ? "● recording" : "idle · hold fn to dictate"
    }

    func setTranscribing() {
        stateLabel.title = "transcribing…"
    }

    private func configureButton(recording: Bool) {
        guard let button = statusItem.button else { return }
        let image = Self.birdImage()
        image?.isTemplate = true
        button.image = image
    }

    // Inlined Lucide bird SVG. Keeping it in source means the executable has
    // no separate resource bundle to install alongside it — true single-binary.
    private static let birdSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
    viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
    stroke-linecap="round" stroke-linejoin="round">\
    <path d="M16 7h.01"/>\
    <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>\
    <path d="m20 7 2 .5-2 .5"/>\
    <path d="M10 18v3"/>\
    <path d="M14 17.75V21"/>\
    <path d="M7 18a6 6 0 0 0 3.84-10.61"/>\
    </svg>
    """

    private static func birdImage() -> NSImage? {
        guard let data = birdSVG.data(using: .utf8),
              let image = NSImage(data: data)
        else { return nil }
        // Menu-bar status icons are nominally 18pt tall; size the SVG to match.
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
