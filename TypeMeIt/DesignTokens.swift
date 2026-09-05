// Generated from design/tokens.json by design/build-tokens.mjs. Do not edit.

import AppKit
import SwiftUI

enum DesignTokens {
    enum Colors {
        private static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
        }

        static let paper = dynamic(light: NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1), dark: NSColor(srgbRed: 0.0431, green: 0.0431, blue: 0.0431, alpha: 1))
        static let paperSunk = dynamic(light: NSColor(srgbRed: 0.9686, green: 0.9686, blue: 0.9686, alpha: 1), dark: NSColor(srgbRed: 0.0235, green: 0.0235, blue: 0.0235, alpha: 1))
        static let paperRaised = dynamic(light: NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1), dark: NSColor(srgbRed: 0.0863, green: 0.0863, blue: 0.0863, alpha: 1))
        static let ink = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 1), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 1))
        static let ink2 = dynamic(light: NSColor(srgbRed: 0.2902, green: 0.2902, blue: 0.2902, alpha: 1), dark: NSColor(srgbRed: 0.7059, green: 0.7059, blue: 0.7059, alpha: 1))
        static let ink3 = dynamic(light: NSColor(srgbRed: 0.4314, green: 0.4314, blue: 0.4314, alpha: 1), dark: NSColor(srgbRed: 0.5412, green: 0.5412, blue: 0.5412, alpha: 1))
        static let rule = dynamic(light: NSColor(srgbRed: 0.8941, green: 0.8941, blue: 0.8941, alpha: 1), dark: NSColor(srgbRed: 0.1490, green: 0.1490, blue: 0.1490, alpha: 1))
        static let ruleControl = dynamic(light: NSColor(srgbRed: 0.5804, green: 0.5804, blue: 0.5804, alpha: 1), dark: NSColor(srgbRed: 0.4314, green: 0.4314, blue: 0.4314, alpha: 1))
        static let slab = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 1), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 1))
        static let onSlab = dynamic(light: NSColor(srgbRed: 1.0000, green: 1.0000, blue: 1.0000, alpha: 1), dark: NSColor(srgbRed: 0.0431, green: 0.0431, blue: 0.0431, alpha: 1))
        static let inkA04 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.04), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.05))
        static let inkA08 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.08), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.10))
        static let inkA12 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.12), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.15))
        static let inkA20 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.20), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.24))
        static let inkA32 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.32), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.36))
        static let inkA48 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.48), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.52))
        static let inkA64 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.64), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.68))
        static let inkA88 = dynamic(light: NSColor(srgbRed: 0.0392, green: 0.0392, blue: 0.0392, alpha: 0.88), dark: NSColor(srgbRed: 0.9804, green: 0.9804, blue: 0.9804, alpha: 0.90))
    }

    enum Fonts {
        static let display1 = Font.system(size: 56, weight: .regular, design: .monospaced)
        static let display2 = Font.system(size: 40, weight: .regular, design: .monospaced)
        static let display3 = Font.system(size: 30, weight: .regular, design: .monospaced)
        static let title = Font.system(size: 22, weight: .semibold, design: .default)
        static let heading = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let ui = Font.system(size: 13, weight: .regular, design: .default)
        static let label = Font.system(size: 11, weight: .semibold, design: .default)
        static let micro = Font.system(size: 10, weight: .regular, design: .default)
    }

    enum Tracking {
        static let display1: CGFloat = -1.57
        static let display2: CGFloat = -0.96
        static let display3: CGFloat = -0.60
        static let title: CGFloat = -0.40
        static let heading: CGFloat = -0.20
        static let body: CGFloat = -0.07
        static let ui: CGFloat = 0.00
        static let label: CGFloat = 0.94
        static let micro: CGFloat = 0.10
    }

    enum Radius {
        static let sm: CGFloat = 5
        static let md: CGFloat = 7
        static let lg: CGFloat = 10
        static let full: CGFloat = 999
    }

    static let hairline: CGFloat = 1
    static let focusWidth: CGFloat = 2
    static let focusOffset: CGFloat = 2

    enum Duration {
        static let n1: TimeInterval = 0.120
        static let n2: TimeInterval = 0.180
        static let n3: TimeInterval = 0.320
        static let n4: TimeInterval = 0.560
    }
}
