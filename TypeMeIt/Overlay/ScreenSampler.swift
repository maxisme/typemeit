import AppKit
import ScreenCaptureKit

/// Reads a few pixels of the screen under the cloud so it can be white over
/// something dark and dark over something light. Needs Screen Recording,
/// which macOS grants for the whole screen or not at all; callers check
/// `CGPreflightScreenCaptureAccess` first. The capture is 8 x 8 pixels,
/// averaged in memory and discarded.
enum ScreenSampler {
    enum Backdrop: Equatable, Sendable { case light, dark }

    static let side = 8

    /// `rect` is in AppKit screen coordinates (origin bottom-left of the main
    /// screen). `excluding` is the overlay's own window number, so the cloud
    /// does not sample itself.
    static func sample(rect: NSRect, excluding windowNumber: Int) async -> Backdrop? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(centre, $0.frame, false) }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let ours = content.windows.filter { $0.windowID == CGWindowID(windowNumber) }
        let filter = SCContentFilter(display: display, excludingWindows: ours)

        // AppKit's y runs up from the bottom of the main screen; the display's
        // runs down from its own top-left corner.
        let mainHeight = NSScreen.screens[0].frame.height
        let local = CGRect(x: rect.minX - display.frame.minX,
                           y: (mainHeight - rect.maxY) - display.frame.minY,
                           width: rect.width, height: rect.height)
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = side
        config.height = side
        config.showsCursor = false
        config.captureResolution = .nominal
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return luminance(of: image).map { $0 > 0.5 ? .light : .dark }
    }

    /// Mean relative luminance across the image, 0 to 1. Nil if the pixels
    /// cannot be read.
    static func luminance(of image: CGImage) -> Double? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        return total / Double(w * h) / 255
    }
}
