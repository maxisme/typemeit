import CoreGraphics
import Testing
@testable import TypeMeIt

struct ScreenSamplerTests {
    private func image(gray: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()!
    }

    @Test func whiteIsOne() {
        #expect(abs(ScreenSampler.luminance(of: image(gray: 1))! - 1) < 0.001)
    }

    @Test func blackIsZero() {
        #expect(ScreenSampler.luminance(of: image(gray: 0)) == 0)
    }

    @Test func midGreyIsAboutHalf() {
        let l = ScreenSampler.luminance(of: image(gray: 0.5))!
        #expect(abs(l - 0.5) < 0.01)
    }
}
