import AppKit
import MenuMeterCore

enum MenuBuilder {
    static func makeMenu(
        snapshot: MetricsSnapshot?,
        loginEnabled: Bool,
        target: AnyObject,
        openSelector: Selector,
        toggleLoginSelector: Selector,
        quitSelector: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        if let snapshot {
            for line in StatusTextFormatter.detailLines(for: snapshot) {
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let openItem = NSMenuItem(
            title: "Etkinlik Monitörü'nü Aç",
            action: openSelector,
            keyEquivalent: ""
        )
        openItem.target = target
        menu.addItem(openItem)

        let loginItem = NSMenuItem(
            title: "Başlangıçta Aç",
            action: toggleLoginSelector,
            keyEquivalent: ""
        )
        loginItem.target = target
        loginItem.state = loginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Çıkış", action: quitSelector, keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = target
        menu.addItem(quitItem)

        return menu
    }
}
