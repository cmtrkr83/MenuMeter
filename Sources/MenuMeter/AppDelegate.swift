import AppKit
import MenuMeterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusController = StatusItemController()
    private let loginItemController = LoginItemController()
    private let engine = MetricsEngine()

    private var latestSnapshot: MetricsSnapshot?
    private var didShowLoginError = false
    private var observerTokens: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        statusController.onOpenActivityMonitor = { [weak self] in
            self?.openActivityMonitor()
        }
        statusController.onMenuNeeded = { [weak self] in
            self?.makeMenu()
        }

        startEngine()
        observeSleepWake()
    }

    private func startEngine() {
        engine.stop()
        engine.start { [weak self] snapshot in
            guard let self else { return }
            self.latestSnapshot = snapshot
            self.statusController.update(snapshot: snapshot)
        }
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.engine.stop()
            }
            observerTokens.append(token)
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.startEngine()
            }
            observerTokens.append(token)
        }
    }

    private func makeMenu() -> NSMenu {
        MenuBuilder.makeMenu(
            snapshot: latestSnapshot,
            loginEnabled: loginItemController.isEnabled,
            target: self,
            openSelector: #selector(openActivityMonitorAction),
            toggleLoginSelector: #selector(toggleLoginItem),
            quitSelector: #selector(quit)
        )
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: "MenuMeter'dan Çık",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func openActivityMonitor() {
        let paths = [
            "/System/Applications/Utilities/Activity Monitor.app",
            "/Applications/Utilities/Activity Monitor.app",
        ]

        for path in paths where FileManager.default.fileExists(atPath: path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: configuration
            ) { _, error in
                if let error {
                    NSLog("MenuMeter: Activity Monitor açılamadı: \(error.localizedDescription)")
                }
            }
            return
        }

        NSLog("MenuMeter: Activity Monitor bulunamadı")
    }

    @objc private func openActivityMonitorAction() {
        openActivityMonitor()
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemController.setEnabled(!loginItemController.isEnabled)
        } catch {
            NSLog("MenuMeter: başlangıç ayarı değiştirilemedi: \(error.localizedDescription)")
            guard !didShowLoginError else { return }
            didShowLoginError = true

            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Başlangıçta Aç değiştirilemedi"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
