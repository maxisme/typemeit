import AppKit

/// Composes the menu bar glyph from the two layers that
/// Support/Icon/generate-menu-icon.sh writes into the asset catalog: the
/// puff's outline and its inner arcs. Each layer is tinted here, so the glyph
/// follows the label colour without being a template image, and the arcs can
/// take a colour of their own.
enum MenuBarIconRenderer {
    /// The recording tint, the same red as the pill's level meter.
    private static let recordingTint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 0.412, blue: 0.38, alpha: 1)
            : NSColor(red: 0.824, green: 0.271, blue: 0.231, alpha: 1)
    }

    static func puff(recording: Bool, transcribing: Bool, secureInput: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in

            func layer(_ name: String, tint: NSColor, alpha: CGFloat = 1) {
                guard let art = NSImage(named: name) else { return }
                // Tinted in its own image rather than in place: `sourceAtop`
                // covers the whole rect, so filling here would repaint every
                // layer already drawn.
                NSImage(size: size, flipped: false) { layerRect in
                    art.draw(in: layerRect)
                    tint.set()
                    layerRect.fill(using: .sourceAtop)
                    return true
                }.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            }

            layer("menu_puff", tint: .labelColor)
            // The arcs carry the state: red while the microphone is open,
            // faded while the recording is being transcribed.
            layer("menu_puff_arcs",
                  tint: recording ? recordingTint : .labelColor,
                  alpha: transcribing ? 0.35 : 1)

            // Secure Input is a slash through the whole mark, the way the OS
            // strikes wifi.slash. The gap under the stroke is cut first so the
            // line reads as lying across the puff rather than dissolving into
            // it.
            if secureInput {
                let start = NSPoint(x: rect.minX + 3, y: rect.maxY - 3)
                let end = NSPoint(x: rect.maxX - 3, y: rect.minY + 3)

                let gap = NSBezierPath()
                gap.move(to: start)
                gap.line(to: end)
                gap.lineWidth = 3.5
                gap.lineCapStyle = .round
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.set()
                gap.stroke()

                NSGraphicsContext.current?.compositingOperation = .sourceOver
                let slash = NSBezierPath()
                slash.move(to: start)
                slash.line(to: end)
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                NSColor.labelColor.set()
                slash.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
