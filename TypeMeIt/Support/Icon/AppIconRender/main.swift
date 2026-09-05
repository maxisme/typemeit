import AppKit
import SwiftUI

// Renders one frozen frame of PuffView for the app icon. Compiled and driven
// by generate-app-icon.sh, which captures the window and masks the result.
//
// Arguments: <expansion> <time> <window points>

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments.dropFirst().map { $0 }
        let expansion = Double(args.first ?? "") ?? 0.85
        let time = Double(args.dropFirst().first ?? "") ?? 100
        let points = Double(args.dropFirst(2).first ?? "") ?? 512

        let size = NSSize(width: points, height: points)
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView:
            PuffView(expansion: expansion, frozenTime: time)
                .frame(width: size.width, height: size.height)
                .background(Color.black))
        window.makeKeyAndOrderFront(nil)
        print("WINDOW \(window.windowNumber)")
        fflush(stdout)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
