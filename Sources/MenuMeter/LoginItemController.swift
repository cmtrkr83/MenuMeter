import Foundation
import ServiceManagement

final class LoginItemController {
    private let defaults: UserDefaults
    private let didAutoEnableKey = "didAutoEnableLoginItem"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enableAtFirstLaunch() {
        guard !defaults.bool(forKey: didAutoEnableKey) else { return }

        if isEnabled {
            defaults.set(true, forKey: didAutoEnableKey)
            return
        }

        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: didAutoEnableKey)
            NSLog("MenuMeter: başlangıçta açma etkinleştirildi")
        } catch {
            NSLog("MenuMeter: başlangıçta açma etkinleştirilemedi: \(error.localizedDescription)")
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
