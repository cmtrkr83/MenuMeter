import AppKit
import MenuMeterCore

final class StatusItemController: NSObject {
    var onOpenActivityMonitor: (() -> Void)?
    var onMenuNeeded: (() -> NSMenu?)?

    private struct Item {
        let metric: Metric
        let statusItem: NSStatusItem
        var lastText: String?
    }

    private var items: [Item] = []

    override init() {
        super.init()

        for metric in Metric.allCases.reversed() {
            let statusItem = NSStatusBar.system.statusItem(
                withLength: NSStatusItem.variableLength
            )
            guard let button = statusItem.button else { continue }

            button.target = self
            button.action = #selector(statusItemClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

            items.append(Item(metric: metric, statusItem: statusItem, lastText: nil))
        }
    }

    func update(snapshot: MetricsSnapshot) {
        for index in items.indices {
            let metric = items[index].metric
            guard let button = items[index].statusItem.button else { continue }

            button.image = StatusIconRenderer.icon(for: metric, snapshot: snapshot)

            let text = StatusTextFormatter.menuBarValue(for: metric, snapshot: snapshot)
            guard text != items[index].lastText else { continue }
            items[index].lastText = text
            button.title = text
            button.setAccessibilityLabel(
                StatusTextFormatter.accessibilityLabel(for: metric, snapshot: snapshot)
            )
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton?) {
        guard
            let sender,
            let index = items.firstIndex(where: { $0.statusItem.button === sender })
        else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let menu = onMenuNeeded?() else { return }
            let statusItem = items[index].statusItem
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onOpenActivityMonitor?()
        }
    }
}
