import AppKit

/// Composes the menu bar glyph from the two layers that
/// Support/Icon/generate-menu-icon.sh writes into the asset catalog: the
/// puff's outline and its inner arcs. Each layer is tinted here, so the glyph
/// follows the label colour without being a template image, and the arcs can
/// take a colour of their own.
enum MenuBarIconRenderer {
    /// The recording tint, the microphone's orange.
    private static let recordingTint = NSColor(srgbRed: 0.961, green: 0.643, blue: 0.290, alpha: 1)
    /// The dev build's puff is dashed, so it is told apart from the
    /// installed release when both are in the menu bar.
    private static let dev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    private static let outlineLayer = dev ? "menu_puff_dashed" : "menu_puff"
    private static let arcsLayer = dev ? "menu_puff_arcs_dashed" : "menu_puff_arcs"

    /// The glyph on its own, for the settings sidebar: the site's favicon,
    /// in ink, at a size of the caller's choosing. Dashed in the dev build
    /// like the menu bar's.
    static func mark(side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            for name in [outlineLayer, arcsLayer] {
                guard let art = NSImage(named: name) else { continue }
                NSImage(size: size, flipped: false) { layerRect in
                    art.draw(in: layerRect)
                    NSColor.labelColor.set()
                    layerRect.fill(using: .sourceAtop)
                    return true
                }.draw(in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
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

            // The whole mark turns orange while the microphone is open. The
            // arcs fade while the recording is being transcribed.
            let tint: NSColor = recording ? recordingTint : .labelColor
            layer(outlineLayer, tint: tint)
            layer(arcsLayer, tint: tint, alpha: transcribing ? 0.35 : 1)

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
