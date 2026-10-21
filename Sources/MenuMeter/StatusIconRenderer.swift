import AppKit
import MenuMeterCore

enum StatusIconRenderer {
    static func icon(
        for metric: Metric,
        snapshot: MetricsSnapshot,
        size: NSSize = NSSize(width: 22, height: 22)
    ) -> NSImage {
        let label = StatusTextFormatter.shortLabel(for: metric)
        let image = NSImage(size: size, flipped: false) { rect in
            drawRing(
                fraction: fraction(for: metric, snapshot: snapshot),
                label: label,
                in: rect
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func fraction(for metric: Metric, snapshot: MetricsSnapshot) -> Double {
        switch metric {
        case .cpu:
            return snapshot.cpu
        case .ram:
            return snapshot.ramFraction
        case .disk:
            return snapshot.diskFraction
        case .gpu:
            return snapshot.gpu ?? 0
        case .network:
            return 0
        }
    }

    private static func drawRing(fraction: Double, label: String, in rect: NSRect) {
        let lineWidth: CGFloat = 1.5
        let radius = max(1, min(rect.width, rect.height) / 2 - lineWidth)
        let center = NSPoint(x: rect.midX, y: rect.midY)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.25).setStroke()
        track.stroke()

        if fraction > 0 {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - CGFloat(360 * max(0, min(1, fraction))),
                clockwise: true
            )
            arc.lineWidth = lineWidth
            NSColor.black.setStroke()
            arc.stroke()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        text.draw(at: NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        ))
    }
}
