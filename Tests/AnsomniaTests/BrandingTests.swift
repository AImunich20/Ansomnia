import CoreGraphics
import SwiftUI
import XCTest
@testable import Ansomnia

/// The marks, checked on rendered geometry. The app icon: the menu bar's
/// running mark, the crescent moon of `MoonMarkGeometry` with the slash
/// through it, on the charcoal tile, the slash cutting its own gap in the
/// crescent and the drawn mark centred on the tile. The menu bar's mark: the
/// plain crescent while idle, slashed while running, monochrome in both.
final class BrandingTests: XCTestCase {
    private let grid = CGRect(x: 0, y: 0, width: MoonMarkGeometry.designSize, height: MoonMarkGeometry.designSize)

    // MARK: - Geometry

    /// The crescent is one closed outline whose horns sit on both circles,
    /// mirror images across the bite's axis; the slash is one open line
    /// along that axis through the grid's centre.
    func testTheCrescentAndTheSlashAreOneLineEachAboutTheBitesAxis() {
        let (p, q) = MoonMarkGeometry.horns
        for horn in [p, q] {
            XCTAssertEqual(distance(horn, MoonMarkGeometry.moonCenter), MoonMarkGeometry.moonRadius, accuracy: 0.001)
            XCTAssertEqual(distance(horn, MoonMarkGeometry.biteCenter), MoonMarkGeometry.biteRadius, accuracy: 0.001)
        }
        // Mirrored across the line y = 24 - x, which carries the bite's axis and the slash.
        XCTAssertEqual(p.x, 24 - q.y, accuracy: 0.001)
        XCTAssertEqual(p.y, 24 - q.x, accuracy: 0.001)
        XCTAssertEqual(MoonMarkGeometry.biteCenter.x + MoonMarkGeometry.biteCenter.y, 24, accuracy: 0.001, "the bite sits on the slash's line")
        let slash = MoonMarkGeometry.slash(in: grid)
        let box = slash.boundingBoxOfPath
        XCTAssertEqual(box.midX, 12, accuracy: 0.001)
        XCTAssertEqual(box.midY, 12, accuracy: 0.001)
        XCTAssertEqual(subpathCount(MoonMarkGeometry.crescent(in: grid)), 1)
        XCTAssertEqual(subpathCount(slash), 1)
        XCTAssertFalse(AppIconArtwork.pathData(slash).contains("Z"), "the slash is an open line")
        XCTAssertTrue(AppIconArtwork.pathData(MoonMarkGeometry.crescent(in: grid)).hasSuffix("Z"), "the crescent is closed")
    }

    /// The crescent is the moon's disc with the bite taken out: inside the
    /// one and outside the other, and filled it is neither empty nor whole.
    func testTheCrescentIsTheMoonWithTheBiteTakenOut() {
        let crescent = MoonMarkGeometry.crescent(in: grid)
        var inside = 0
        for y in stride(from: CGFloat(0.25), to: 24, by: 0.5) {
            for x in stride(from: CGFloat(0.25), to: 24, by: 0.5) {
                let point = CGPoint(x: x, y: y)
                let inMoon = distance(point, MoonMarkGeometry.moonCenter) < MoonMarkGeometry.moonRadius - 0.05
                let inBite = distance(point, MoonMarkGeometry.biteCenter) < MoonMarkGeometry.biteRadius - 0.05
                let outMoon = distance(point, MoonMarkGeometry.moonCenter) > MoonMarkGeometry.moonRadius + 0.05
                let outBite = distance(point, MoonMarkGeometry.biteCenter) > MoonMarkGeometry.biteRadius + 0.05
                if inMoon && outBite { XCTAssertTrue(crescent.contains(point), "\(point) is on the crescent") }
                if outMoon || inBite { XCTAssertFalse(crescent.contains(point), "\(point) is off the crescent") }
                if crescent.contains(point) { inside += 1 }
            }
        }
        XCTAssertGreaterThan(inside, 2304 / 8, "the crescent has body")
        XCTAssertLessThan(inside, 2304 / 3, "the crescent is not the whole moon")
    }

    func testTheStrokedMarkFitsInsideTheSeventeenPointFrame() {
        let frame = CGRect(x: 0, y: 0, width: 17, height: 17)
        let width = MoonMarkGeometry.lineWidth(for: frame.width)
        let stroked = CGMutablePath()
        for path in [MoonMarkGeometry.crescent(in: frame), MoonMarkGeometry.slash(in: frame)] {
            stroked.addPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
        }
        let box = stroked.boundingBoxOfPath
        // Enough headroom that a sub-pixel rasteriser does not clip the caps.
        let headroom = 0.4 * frame.width / MoonMarkGeometry.designSize
        XCTAssertTrue(frame.insetBy(dx: headroom, dy: headroom).contains(box), "the view's frame clips the mark: \(box)")
    }

    // MARK: - The app icon

    /// Pixel for pixel, the icon's ink is the crescent with a gap cut along
    /// the slash, and the slash in it, in the icon's mark square, and
    /// nothing else.
    func testTheIconDrawsTheSlashedMoonAndNothingElse() throws {
        for pixels in [256, 16] {
            let drawn = IconPixels(try XCTUnwrap(AppIconArtwork.render(pixels: pixels)))
            let scale = CGFloat(pixels) / AppIconArtwork.canvas
            let mark = AppIconArtwork.mark
            let line = max(MoonMarkGeometry.lineWidth(for: mark.width), AppIconArtwork.minimumStrokePixels / scale)
            let gap = line + MoonMarkGeometry.gapWidth(for: mark.width) - MoonMarkGeometry.lineWidth(for: mark.width)
            let expected = Raster(size: pixels) { ctx in
                ctx.scaleBy(x: scale, y: scale)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.setLineWidth(line)
                ctx.addPath(MoonMarkGeometry.crescent(in: mark))
                ctx.strokePath()
                ctx.setBlendMode(.clear)
                ctx.setLineWidth(gap)
                ctx.addPath(MoonMarkGeometry.slash(in: mark))
                ctx.strokePath()
                ctx.setBlendMode(.normal)
                ctx.setLineWidth(line)
                ctx.addPath(MoonMarkGeometry.slash(in: mark))
                ctx.strokePath()
            }
            // Coverage against coverage, not each against a half-way
            // threshold: at 16 pixels most of the ink is edge pixels.
            let tileInk = luminance(BrandPalette.midnight), markInk = luminance(BrandPalette.moonWhite)
            var mismatches = 0
            var weight: CGFloat = 0
            for y in 0..<pixels {
                for x in 0..<pixels where drawn.alpha(x, y) > 0.99 {
                    let coverage = min(max((drawn.luminance(x, y) - tileInk) / (markInk - tileInk), 0), 1)
                    if abs(coverage - expected.alpha(x, y)) > 0.1 { mismatches += 1 }
                    weight += coverage
                }
            }
            XCTAssertGreaterThan(weight, CGFloat(pixels * pixels) / 60, "the mark is drawn at \(pixels) pixels")
            XCTAssertLessThanOrEqual(mismatches, pixels * pixels / 2000, "the \(pixels)px icon differs from the slashed moon at \(mismatches) pixels")
        }
    }

    /// The 24-unit grid is 76% of the tile and centred on it, and so is
    /// what is drawn: the slash runs corner to corner through the grid's
    /// centre and the crescent lies within its reach.
    func testTheMarkKeepsItsShareOfTheTileAndItsInkIsCentredOnIt() {
        let tile = AppIconArtwork.tile
        let mark = AppIconArtwork.mark
        XCTAssertEqual(mark.width, tile.width * 0.76, accuracy: 0.001)
        XCTAssertEqual(mark.height, mark.width)
        XCTAssertEqual(mark.midX, tile.midX, accuracy: 0.001)
        XCTAssertEqual(mark.midY, tile.midY, accuracy: 0.001)
        let inked = AppIconArtwork.inked(in: mark)
        // Within a twentieth of a canvas unit: CoreGraphics draws the arcs
        // as cubics, whose bounds stray from the circles' by a hair.
        XCTAssertEqual(inked.midX, tile.midX, accuracy: 0.05, "the ink is centred across the tile")
        XCTAssertEqual(inked.midY, tile.midY, accuracy: 0.05, "the ink is centred down the tile")
        XCTAssertTrue(tile.insetBy(dx: 40, dy: 40).contains(inked), "the ink stays well inside the tile: \(inked)")
        XCTAssertEqual(tile, CGRect(x: 100, y: 100, width: 824, height: 824))
        XCTAssertEqual(AppIconArtwork.cornerShare, 0.2237)
    }

    /// Where the slash crosses the moon's rim, the rim is cut back either
    /// side of the slash, at every size where the gap spans whole pixels
    /// (from 64; at 32 it is about a pixel and at 16 under one).
    func testTheSlashCutsAGapInTheCrescentAtEverySize() throws {
        let probes = Probes(in: AppIconArtwork.mark)
        let tileInk = luminance(BrandPalette.midnight)
        for pixels in [64, 256, 1024] {
            let px = IconPixels(try XCTUnwrap(AppIconArtwork.render(pixels: pixels)))
            let scale = CGFloat(pixels) / AppIconArtwork.canvas
            func at(_ p: CGPoint) -> CGFloat { px.luminance(Int(p.x * scale), Int(p.y * scale)) }
            XCTAssertGreaterThan(at(probes.rim), 0.6, "\(pixels)px: the rim is drawn")
            XCTAssertGreaterThan(at(probes.slash), 0.6, "\(pixels)px: the slash is drawn")
            XCTAssertEqual(at(probes.gap), tileInk, accuracy: 0.08, "\(pixels)px: the rim is cut back beside the slash")
        }
    }

    // MARK: - The menu bar mark

    /// Idle: the crescent alone, nothing along the slash's line and the rim
    /// unbroken where the slash would cross it. Running: the slash is drawn
    /// and the rim is cut back beside it. Monochrome in both states, in
    /// both schemes, with and without Reduce Motion.
    @MainActor
    func testTheMarkIsACrescentWhileIdleAndSlashedWhileRunning() throws {
        let scale: CGFloat = 4
        let probes = Probes(in: CGRect(x: 0, y: 0, width: 17 * scale, height: 17 * scale))
        func pixel(_ p: CGPoint) -> (Int, Int) { (Int(p.x), Int(p.y)) }
        for (scheme, reduceMotion) in product([ColorScheme.light, .dark], [true, false]) {
            let idle = try Raster.render(MoonMarkView(isRunning: false, reduceMotion: reduceMotion), scheme: scheme, scale: scale)
            let running = try Raster.render(MoonMarkView(isRunning: true, reduceMotion: reduceMotion), scheme: scheme, scale: scale)
            let label = "\(scheme), reduce motion \(reduceMotion)"

            // `.primary` is the system label colour, which is itself only 85% opaque.
            XCTAssertGreaterThan(idle.alpha(pixel(probes.rim)), 0.5, "\(label): the crescent is drawn while idle")
            XCTAssertGreaterThan(idle.alpha(pixel(probes.gap)), 0.5, "\(label): the rim is unbroken while idle")
            XCTAssertLessThan(idle.alpha(pixel(probes.slash)), 0.05, "\(label): no slash while idle")

            XCTAssertGreaterThan(running.alpha(pixel(probes.rim)), 0.5, "\(label): the crescent stays while running")
            XCTAssertGreaterThan(running.alpha(pixel(probes.slash)), 0.5, "\(label): the slash is drawn while running")
            XCTAssertLessThan(running.alpha(pixel(probes.gap)), 0.05, "\(label): the rim is cut back beside the slash")

            let idleInk = idle.rgb(pixel(probes.rim)), runningInk = running.rgb(pixel(probes.slash))
            XCTAssertLessThan(idleInk.saturation, 0.1, "\(label): the idle mark is monochrome: \(idleInk)")
            XCTAssertLessThan(runningInk.saturation, 0.1, "\(label): the running mark is monochrome: \(runningInk)")
            XCTAssertEqual(idleInk.luminance, runningInk.luminance, accuracy: 0.05, "\(label): both states share one ink")
            switch scheme {
            case .light: XCTAssertLessThan(idleInk.luminance, 0.3, "light: ink is dark")
            case .dark: XCTAssertGreaterThan(idleInk.luminance, 0.7, "dark: ink is light")
            @unknown default: XCTFail("unexpected scheme")
            }
            let ink = running.count { $0.alpha > 0.5 }
            XCTAssertLessThan(ink, running.total / 3, "\(label): the mark must not flood its frame")
        }
    }

    /// The slash draws in along its length, and under Reduce Motion it is
    /// always whole and fades instead.
    func testTheSlashDrawsInAndOnlyFadesUnderReduceMotion() {
        for progress in [CGFloat(0), 0.3, 1] {
            let moving = MoonMarkView(progress: progress, reduceMotion: false)
            XCTAssertEqual(moving.slashLength, progress)
            XCTAssertEqual(moving.slashOpacity, progress > 0 ? 1 : 0)
            let reduced = MoonMarkView(progress: progress, reduceMotion: true)
            XCTAssertEqual(reduced.slashLength, 1)
            XCTAssertEqual(reduced.slashOpacity, progress)
        }
        // A spring's overshoot either way stays within the line.
        XCTAssertEqual(MoonMarkView(progress: 1.08, reduceMotion: false).slashLength, 1)
        XCTAssertEqual(MoonMarkView(progress: -0.05, reduceMotion: false).slashOpacity, 0)
    }

    // MARK: - Helpers

    private func luminance(_ rgb: BrandPalette.RGB) -> CGFloat {
        0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func product<A, B>(_ a: [A], _ b: [B]) -> [(A, B)] {
        a.flatMap { x in b.map { (x, $0) } }
    }

    private func subpathCount(_ path: CGPath) -> Int {
        var moves = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { moves += 1 }
        }
        return moves
    }

    /// Points worth probing, on the grid mapped into `rect`, derived from
    /// the geometry so the tests follow it rather than pinning pixels.
    private struct Probes {
        /// On the moon's rim, well away from the slash.
        let rim: CGPoint
        /// On the slash, out in the bite where there is no crescent.
        let slash: CGPoint
        /// On the rim just beside the slash where the slash crosses it:
        /// inked when unslashed, cleared by the gap when slashed.
        let gap: CGPoint

        init(in rect: CGRect) {
            let t = MoonMarkGeometry.gridTransform(in: rect)
            let c = MoonMarkGeometry.moonCenter, r = MoonMarkGeometry.moonRadius
            rim = CGPoint(x: c.x - r, y: c.y).applying(t)
            slash = MoonMarkGeometry.biteCenter.applying(t)
            // The slash leaves the moon down and to the left, along (-1, 1).
            let crossing = CGPoint(x: c.x - r / 2.squareRoot(), y: c.y + r / 2.squareRoot())
            // Off the slash, half way between the line's edge (0.75 units)
            // and the gap's (2), along the perpendicular (1, 1).
            let lineEdge = MoonMarkGeometry.strokeUnits / 2
            let gapEdge = lineEdge + MoonMarkGeometry.gapUnits
            let offset = (lineEdge + gapEdge) / 2 / 2.squareRoot()
            let angle = atan2(crossing.y + offset - c.y, crossing.x + offset - c.x)
            gap = CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle)).applying(t)
        }
    }
}

/// RGBA8 bitmap with the design's y-down orientation, drawn by CoreGraphics
/// or filled from a rendered SwiftUI view.
struct Raster {
    struct RGB: CustomStringConvertible {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        var luminance: CGFloat { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
        var saturation: CGFloat {
            let hi = max(red, green, blue)
            let lo = min(red, green, blue)
            return hi == 0 ? 0 : (hi - lo) / hi
        }
        var description: String { "rgb(\(red), \(green), \(blue))" }
    }

    let width: Int
    let height: Int
    private let data: [UInt8]

    var total: Int { width * height }

    init(size: Int, draw: (CGContext) -> Void) {
        self.init(width: size, height: size) { ctx in
            // Design coordinates are y-down; CoreGraphics bitmaps are y-up.
            ctx.translateBy(x: 0, y: CGFloat(size))
            ctx.scaleBy(x: 1, y: -1)
            draw(ctx)
        }
    }

    private init(width: Int, height: Int, draw: (CGContext) -> Void) {
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            draw(ctx)
        }
        data = bytes
    }

    /// Renders a SwiftUI view under `scheme` at `scale` into a bitmap whose
    /// (0,0) is the view's top-left.
    @MainActor
    static func render<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat) throws -> Raster {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image")
        return Raster(width: image.width, height: image.height) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    private func offset(_ x: Int, _ y: Int) -> Int {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel (\(x), \(y)) outside \(width)x\(height)")
        return (y * width + x) * 4
    }

    func alpha(_ x: Int, _ y: Int) -> CGFloat {
        CGFloat(data[offset(x, y) + 3]) / 255
    }

    func alpha(_ p: (Int, Int)) -> CGFloat { alpha(p.0, p.1) }

    /// Straight (un-premultiplied) colour at a pixel.
    func rgb(_ p: (Int, Int)) -> RGB {
        let o = offset(p.0, p.1)
        let a = max(CGFloat(data[o + 3]), 1)
        return RGB(red: CGFloat(data[o]) / a, green: CGFloat(data[o + 1]) / a, blue: CGFloat(data[o + 2]) / a)
    }

    func count(where pass: ((alpha: CGFloat, rgb: RGB)) -> Bool) -> Int {
        var n = 0
        for y in 0..<height {
            for x in 0..<width where pass((alpha(x, y), rgb((x, y)))) { n += 1 }
        }
        return n
    }
}

/// Straight RGBA at integer pixels of a rendered CGImage, (0,0) top-left.
struct IconPixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        data = bytes
    }

    private func offset(_ x: Int, _ y: Int) -> Int {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel (\(x), \(y)) outside \(width)x\(height)")
        return (y * width + x) * 4
    }

    func alpha(_ x: Int, _ y: Int) -> CGFloat {
        CGFloat(data[offset(x, y) + 3]) / 255
    }

    func luminance(_ x: Int, _ y: Int) -> CGFloat {
        let o = offset(x, y)
        let a = max(CGFloat(data[o + 3]), 1)
        let r = CGFloat(data[o]) / a, g = CGFloat(data[o + 1]) / a, b = CGFloat(data[o + 2]) / a
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Pixels where any channel of the two images differs by more than `tolerance` (0 to 255).
    func differences(from other: IconPixels, tolerance: Int) -> Int {
        precondition(width == other.width && height == other.height)
        var n = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            for c in 0..<4 where abs(Int(data[i + c]) - Int(other.data[i + c])) > tolerance {
                n += 1
                break
            }
        }
        return n
    }
}
